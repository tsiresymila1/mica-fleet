import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/network/token_store.dart';
import 'package:mica_fleet/features/auth/data/auth_remote_data_source.dart';
import 'package:mica_fleet/features/auth/data/datasources/auth_local_ds.dart';
import 'package:mica_fleet/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';

class _Remote implements AuthRemoteDataSource {
  @override
  Future<LoginResult> login(String login, String password) async => LoginResult(
    token: 'token',
    agentId: login,
    agentNom: 'Eddy',
    mines: const [],
    depots: const [],
    communes: const [RemoteCommune(24091, 'Andilana', 'Ambohidratrimo', true)],
  );
}

class _MemoryTokenStore extends SecureTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> save(String token) async => this.token = token;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('le login conserve les communes dans le cache Drift', () async {
    final repository = AuthRepositoryImpl(
      AuthLocalDataSource(db),
      _Remote(),
      _MemoryTokenStore(),
    );

    final result = await repository.login('eddy', 'secret');

    expect(result.isRight(), isTrue);
    final commune = (await db.select(db.communes).get()).single;
    expect(commune.id, 24091);
    expect(commune.nom, 'Andilana');
    expect(commune.district, 'Ambohidratrimo');
    expect(commune.actif, isTrue);
  });
}
