import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../data/repositories/transport_repository_impl.dart';
import '../../domain/repositories/transport_repository.dart';

final transportRepoProvider = Provider<TransportRepository>((ref) =>
    TransportRepositoryImpl(
        ref.watch(dbProvider), ref.watch(localSyncStoreProvider)));
