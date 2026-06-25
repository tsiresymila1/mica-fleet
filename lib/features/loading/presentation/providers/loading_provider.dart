import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/loading_id.dart';
import '../../../delais/domain/delai_alert_planner.dart';
import '../../../delais/domain/entities/delai_config.dart';
import '../../data/repositories/loading_repository_impl.dart';
import '../../domain/entities/chargement.dart';
import '../../domain/entities/mine_chargement.dart';
import '../../domain/repositories/loading_repository.dart';
import '../../domain/usecases/add_mine_to_chargement.dart';
import '../../domain/usecases/validate_chargement.dart';

final loadingRepoProvider = Provider<LoadingRepository>((ref) =>
    LoadingRepositoryImpl(
        ref.watch(dbProvider), ref.watch(localSyncStoreProvider)));

final addMineUsecaseProvider = Provider((ref) => AddMineToChargement());
final validateChargementUsecaseProvider =
    Provider((ref) => ValidateChargement());

/// État du chargement en cours de saisie (en mémoire jusqu'à validation).
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

  Either<Failure, Unit> addMine(MineChargement m) {
    final current = state;
    if (current == null) {
      return left(const Failure.validation('Aucun chargement en cours'));
    }
    final res = ref.read(addMineUsecaseProvider)(current, m);
    return res.match(left, (updated) {
      state = updated;
      return right(unit);
    });
  }

  /// Valide la cohérence puis persiste (chargement + mines + journal sync).
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
          // Programme les rappels de délai (livraison au dépôt).
          const config = DelaiConfig();
          final rappels = DelaiAlertPlanner().planifier(
              persisted.dateCreation, config.directVersDepot,
              seuil: config.seuilAlerteAvant);
          await ref
              .read(notificationServiceProvider)
              .scheduleRappels(persisted.id.hashCode & 0x7ff0, rappels);
        });
        return saved;
      },
    );
  }
}
