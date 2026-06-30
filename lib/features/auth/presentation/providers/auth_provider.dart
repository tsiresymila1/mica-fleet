import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/failure.dart';
import '../../data/datasources/auth_local_ds.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/fournisseur.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/usecases/login.dart';

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => AuthRepositoryImpl(AuthLocalDataSource(ref.watch(dbProvider))));

final loginProvider =
    Provider<Login>((ref) => Login(ref.watch(authRepositoryProvider)));

/// État de session courant (null = déconnecté). Pilote la garde du routeur.
final authControllerProvider =
    NotifierProvider<AuthController, Fournisseur?>(AuthController.new);

class AuthController extends Notifier<Fournisseur?> {
  @override
  Fournisseur? build() => null;

  /// Restaure une session existante au démarrage.
  void setSession(Fournisseur? f) => state = f;

  Future<Either<Failure, Fournisseur>> login(String identifiant) async {
    final res = await ref.read(loginProvider)(identifiant);
    res.match((_) {}, (f) => state = f);
    return res;
  }

  void logout() => state = null;
}
