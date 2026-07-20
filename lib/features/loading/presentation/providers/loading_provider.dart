import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/loading_id.dart';
import '../../../delais/domain/delai_alert_planner.dart';
import '../../../delais/domain/entities/delai_config.dart';
import '../../../trip/presentation/trip_provider.dart';
import '../../data/repositories/loading_repository_impl.dart';
import '../../domain/entities/chargement.dart';
import '../../domain/entities/lot.dart';
import '../../domain/repositories/loading_repository.dart';
import '../../domain/usecases/add_lot_to_chargement.dart';
import '../../domain/usecases/validate_chargement.dart';

final loadingRepoProvider = Provider<LoadingRepository>((ref) =>
    LoadingRepositoryImpl(ref.watch(dbProvider),
        ref.watch(localSyncStoreProvider), ref.watch(journalServiceProvider)));

final addLotUsecaseProvider = Provider((ref) => AddLotToChargement());
final validateChargementUsecaseProvider =
    Provider((ref) => ValidateChargement());

/// Session en cours de saisie (en mémoire jusqu'à validation).
final chargementControllerProvider =
    NotifierProvider<ChargementController, Chargement?>(ChargementController.new);

class ChargementController extends Notifier<Chargement?> {
  @override
  Chargement? build() => null;

  Future<void> startNew(String fournisseurId) async {
    final repo = ref.read(loadingRepoProvider);
    final now = DateTime.now();
    final seq = await repo.nextSequence(now.year);
    state = Chargement(
      id: buildLoadingId(now.year, seq),
      fournisseurId: fournisseurId,
      dateCreation: now,
    );
  }

  /// Référence de lot optionnelle (regroupe plusieurs camions côté Odoo).
  void setLotReference(String? v) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
        lotReference: v == null || v.trim().isEmpty ? null : v.trim());
  }

  /// Ajoute un LOT (chargement d'UNE mine, indivisible).
  Either<Failure, Unit> addLot(Lot lot) {
    final current = state;
    if (current == null) {
      return left(const Failure.validation('Aucun chargement en cours'));
    }
    final res = ref.read(addLotUsecaseProvider)(current, lot);
    return res.match(left, (updated) {
      state = updated;
      return right(unit);
    });
  }

  /// Valide puis persiste la session + ses lots (aucun envoi ici : la sync
  /// part à l'arrivée de chaque lot).
  Future<Either<Failure, Chargement>> validateAndPersist() async {
    final current = state;
    if (current == null) {
      return left(const Failure.validation('Aucun chargement en cours'));
    }
    final validated = ref.read(validateChargementUsecaseProvider)(current);
    return validated.match(
      (f) => Future.value(left(f)),
      (c) async {
        final saved = await ref.read(loadingRepoProvider).persist(c);
        await saved.match((_) async {}, (persisted) async {
          state = null;
          const config = DelaiConfig();
          final rappels = DelaiAlertPlanner().planifier(
              persisted.dateCreation, config.directVersDepot,
              seuil: config.seuilAlerteAvant);
          await ref.read(notificationServiceProvider).scheduleRappels(
              persisted.id.hashCode & 0x7ff0, rappels,
              payload: persisted.id);
          await ref.read(tripTrackerProvider).start(persisted.id);
        });
        return saved;
      },
    );
  }
}
