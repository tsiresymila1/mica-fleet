import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/repositories/loading_repository_impl.dart';
import '../../domain/usecases/create_chargement.dart';

final loadingRepoProvider = Provider((ref) => LoadingRepositoryImpl(
    ref.watch(dbProvider), ref.watch(localSyncStoreProvider)));

final createChargementProvider =
    Provider((ref) => CreateChargement(ref.watch(loadingRepoProvider)));
