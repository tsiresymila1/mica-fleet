import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';

final triggerSyncProvider = Provider((ref) => ref.watch(syncEngineProvider));
