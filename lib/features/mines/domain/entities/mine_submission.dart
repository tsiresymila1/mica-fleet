import '../../../capture/domain/entities/captured_photo.dart';

enum MineSubmissionState {
  localPending('local_pending'),
  awaitingAttachments('awaiting_attachments'),
  pendingValidation('pending_validation'),
  approved('approved'),
  rejected('rejected'),
  hidden('hidden');

  final String apiValue;
  const MineSubmissionState(this.apiValue);

  static MineSubmissionState fromValue(String value) => values.firstWhere(
    (state) => state.apiValue == value,
    orElse: () => MineSubmissionState.localPending,
  );
}

class MineSubmissionPhoto {
  final String key;
  final CapturedPhoto photo;
  final bool uploaded;

  const MineSubmissionPhoto({
    required this.key,
    required this.photo,
    this.uploaded = false,
  });
}

class MineSubmission {
  final String payloadId;
  final String deviceUuid;
  final String nom;
  final int? communeId;
  final String? agentLogin;
  final MineSubmissionState state;
  final int? serverId;
  final String? approvedMineId;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MineSubmissionPhoto> photos;

  const MineSubmission({
    required this.payloadId,
    required this.deviceUuid,
    required this.nom,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.photos,
    this.communeId,
    this.agentLogin,
    this.serverId,
    this.approvedMineId,
    this.rejectionReason,
  });
}
