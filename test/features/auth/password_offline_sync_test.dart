import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/network/token_store.dart';
import 'package:mica_fleet/features/auth/data/auth_remote_data_source.dart';
import 'package:mica_fleet/features/auth/data/datasources/auth_local_ds.dart';
import 'package:mica_fleet/features/auth/data/password_secret_store.dart';
import 'package:mica_fleet/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';
import 'package:mica_fleet/features/sync/data/mock_remote_data_source.dart';
import 'package:mica_fleet/features/sync/data/sync_engine.dart';

class _AuthRemote implements AuthRemoteDataSource {
  @override
  Future<LoginResult> login(String login, String password) =>
      throw UnimplementedError();
}

class _MemoryTokenStore extends SecureTokenStore {
  @override
  Future<String?> read() async => 'token';

  @override
  Future<void> save(String token) async {}
}

class _PasswordRemote extends MockRemoteDataSource {
  bool offline = true;
  final calls = <({String current, String next})>[];

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/password/change'),
        reason: 'offline',
      );
    }
    calls.add((current: currentPassword, next: newPassword));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'un changement hors ligne est appliqué localement puis synchronisé',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = AppDatabase.memory();
      addTearDown(db.close);
      const secrets = PasswordSecretStore();
      const login = 'eddy';
      const oldPassword = 'ancien-secret';
      const newPassword = 'nouveau-secret';
      await secrets.saveVerifier(login, oldPassword);
      final remote = _PasswordRemote();
      final repository = AuthRepositoryImpl(
        AuthLocalDataSource(db),
        _AuthRemote(),
        _MemoryTokenStore(),
        secrets,
        remote,
      );

      final changed = await repository.changePassword(
        login: login,
        currentPassword: oldPassword,
        newPassword: newPassword,
      );

      expect(changed.getRight().toNullable(), isTrue);
      expect(await secrets.verify(login, newPassword), isTrue);
      expect(await secrets.verify(login, oldPassword), isFalse);
      expect((await secrets.pending())?.currentPassword, oldPassword);
      expect((await secrets.pending())?.newPassword, newPassword);

      remote.offline = false;
      await SyncEngine(DriftLocalSyncStore(db), remote, db, secrets).sync();

      expect(remote.calls, [(current: oldPassword, next: newPassword)]);
      expect(await secrets.pending(), isNull);
      expect(await secrets.verify(login, newPassword), isTrue);
    },
  );
}
