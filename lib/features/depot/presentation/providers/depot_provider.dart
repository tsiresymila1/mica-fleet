import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/repositories/depot_repository_impl.dart';
import '../../domain/repositories/depot_repository.dart';

final depotRepoProvider = Provider<DepotRepository>((ref) => DepotRepositoryImpl(
    ref.watch(dbProvider), ref.watch(localSyncStoreProvider)));
