import 'package:freezed_annotation/freezed_annotation.dart';
part 'sync_operation.freezed.dart';

enum SyncStatus { pending, syncing, synced, failed }

enum SyncOpType { create, update, delete }

@freezed
abstract class SyncOperation with _$SyncOperation {
  const factory SyncOperation({
    required String opId,
    required String entityType,
    required String entityId,
    required SyncOpType opType,
    required Map<String, dynamic> payload,
    @Default(SyncStatus.pending) SyncStatus status,
    @Default(0) int attempts,
    String? lastError,
    required DateTime createdAt,
    DateTime? nextRetryAt,
    int? odooId,
    DateTime? syncedAt,
    String? agentLogin, // fournisseur (submit terrain_api)
    double? gpsLat,
    double? gpsLon,
    double? gpsAccuracy,
  }) = _SyncOperation;
}
