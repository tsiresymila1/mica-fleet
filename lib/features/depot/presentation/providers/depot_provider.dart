import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/repositories/depot_repository_impl.dart';
import '../../domain/entities/depot.dart';
import '../../domain/repositories/depot_repository.dart';
import '../../domain/usecases/detect_depot.dart';
import '../../domain/usecases/validate_arrivee.dart';

final depotRepoProvider = Provider<DepotRepository>((ref) => DepotRepositoryImpl(
    ref.watch(dbProvider), ref.watch(localSyncStoreProvider)));

final detectDepotProvider = Provider((ref) => DetectDepot());

final validateArriveeProvider =
    Provider((ref) => ValidateArrivee(ref.watch(detectDepotProvider)));

final activeDepotsProvider = FutureProvider<List<Depot>>(
    (ref) => ref.watch(depotRepoProvider).activeDepots());
