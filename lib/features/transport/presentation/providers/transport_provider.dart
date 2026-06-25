import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/repositories/transport_repository_impl.dart';
import '../../domain/entities/transbordement.dart';
import '../../domain/repositories/transport_repository.dart';
import '../../domain/usecases/add_transbordement.dart';
import '../../domain/usecases/remove_transbordement.dart';
import '../../domain/usecases/validate_transbordement.dart';

const kRayonTransbordementMetres = 20.0; // ponytail: paramétrable Odoo plus tard

final transportRepoProvider = Provider<TransportRepository>((ref) =>
    TransportRepositoryImpl(ref.watch(dbProvider),
        ref.watch(localSyncStoreProvider), ref.watch(journalServiceProvider)));

final _addProvider = Provider((ref) => AddTransbordement());
final _removeProvider = Provider((ref) => RemoveTransbordement());
final _validateProvider = Provider((ref) => ValidateTransbordement());

/// Chaîne de transbordements 0..N en cours d'édition pour un chargement.
final chaineControllerProvider =
    NotifierProvider<ChaineController, List<Transbordement>>(
        ChaineController.new);

class ChaineController extends Notifier<List<Transbordement>> {
  @override
  List<Transbordement> build() => const [];

  Future<void> load(String chargementId) async {
    state = await ref.read(transportRepoProvider).chaineFor(chargementId);
  }

  void addMaillon(Transbordement maillon) {
    final ajoutee = ref.read(_addProvider)(state, maillon);
    state = ref.read(_validateProvider)(ajoutee, kRayonTransbordementMetres);
  }

  void removeMaillon(int ordre) {
    final reduite = ref.read(_removeProvider)(state, ordre);
    state = ref.read(_validateProvider)(reduite, kRayonTransbordementMetres);
  }

  bool get chaineCoherente => ref.read(_validateProvider).chaineCoherente(state);

  Future<bool> persist(String chargementId) async {
    final res =
        await ref.read(transportRepoProvider).persistChaine(chargementId, state);
    return res.isRight();
  }
}
