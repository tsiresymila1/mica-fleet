import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../../depot/presentation/providers/depot_provider.dart';
import '../../data/repositories/transport_repository_impl.dart';
import '../../domain/repositories/transport_repository.dart';
import '../../domain/usecases/remove_transbordement.dart';
import '../../domain/usecases/validate_transbordement.dart';

const kRayonTransbordementMetres = 20.0; // ponytail: paramétrable Odoo plus tard

final transportRepoProvider = Provider<TransportRepository>((ref) =>
    TransportRepositoryImpl(ref.watch(dbProvider),
        ref.watch(localSyncStoreProvider), ref.watch(journalServiceProvider)));

final validateTransbordementProvider =
    Provider((ref) => ValidateTransbordement());

final removeTransbordementProvider =
    Provider((ref) => RemoveTransbordement());

/// Lots encore en route d'une session (candidats à un transbordement).
final lotsEnCoursProvider = FutureProvider.autoDispose
    .family<List<({String id, String mineId, String? couleur})>, String>(
        (ref, sessionId) => ref.read(depotRepoProvider).lotsEnCours(sessionId));
