import '../entities/sync_operation.dart';

class RemoteMine {
  final String id, nom;
  final double lat, lon, rayonMetres;
  final String? district, fokontany, commune, region;
  final String? reference;
  final String? note;
  final DateTime? createdAt;
  final bool actif;
  RemoteMine(
    this.id,
    this.nom,
    this.lat,
    this.lon,
    this.rayonMetres,
    this.district,
    this.commune,
    this.region,
    this.actif, {
    this.reference,
    this.note,
    this.createdAt,
    this.fokontany,
  });
}

class RemoteDepot {
  final String id, nom;
  final double lat, lon, rayonMetres;
  final bool actif;

  const RemoteDepot(
    this.id,
    this.nom,
    this.lat,
    this.lon,
    this.rayonMetres,
    this.actif,
  );
}

/// Vue utile du payload renvoyé par `GET /api/tracking/lots`.
///
/// Le backend renvoie le même objet que `payload` dans le submit, enrichi de
/// la référence et de la décision de validation. Seuls les champs nécessaires
/// au cache et aux listes sont projetés ici ; les champs supplémentaires du
/// payload restent volontairement tolérés par le parseur.
class RemoteLot {
  final String payloadId;
  final String sessionId;
  final String? reference;
  final String validationStatus;
  final String? validationReason;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String mineId;
  final String mineName;
  final String? mineReference;
  final String? mineNote;
  final String? color;
  final double? estimatedQuantity;
  final String transportStatus;
  final int? score;

  const RemoteLot({
    required this.payloadId,
    required this.sessionId,
    required this.reference,
    required this.validationStatus,
    required this.validationReason,
    required this.createdAt,
    required this.updatedAt,
    required this.mineId,
    required this.mineName,
    required this.mineReference,
    required this.mineNote,
    required this.color,
    required this.estimatedQuantity,
    required this.transportStatus,
    required this.score,
  });
}

/// Une photo à uploader : clé (slot), fichier local, hash (idempotence).
class PhotoPart {
  final String key;
  final String path;
  final String hash;
  PhotoPart(this.key, this.path, this.hash);
}

class PasswordChangeRejected implements Exception {
  final String message;
  const PasswordChangeRejected(this.message);

  @override
  String toString() => message;
}

abstract class RemoteDataSource {
  /// Push idempotent : Odoo déduplique sur op.opId. Lève en cas d'échec réseau.
  /// Renvoie l'id du record créé/mis à jour côté Odoo (odoo_id), ou null.
  Future<int?> pushOperation(SyncOperation op);

  /// Upload d'UNE photo multipart. [payloadId] = UUID envoyé dans payload.id ;
  /// [deviceUuid] = clé d'idempotence du submit. Le triplet payload/key/hash
  /// rend le rejeu sûr côté serveur. Lève en cas d'échec réseau.
  Future<void> uploadPhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  );

  /// Upload unitaire d'une preuve de position pour une proposition de mine.
  Future<void> uploadMinePhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  );

  /// Pull du référentiel mines.
  Future<List<RemoteMine>> fetchMines();

  /// Pull du référentiel dépôts.
  Future<List<RemoteDepot>> fetchDepots();

  /// Pull des lots accessibles à l'utilisateur connecté. Une implémentation
  /// vide garde les doubles de test et anciens connecteurs compatibles.
  Future<List<RemoteLot>> fetchLots() async => const [];

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => throw UnimplementedError('Password API not configured');
}
