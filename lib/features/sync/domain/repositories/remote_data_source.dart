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

class RemoteCommune {
  final int id;
  final String name;
  final String? district;
  final bool actif;

  const RemoteCommune({
    required this.id,
    required this.name,
    this.district,
    required this.actif,
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

class RemoteLotPhoto {
  final String role;
  final String key;
  final String? url;
  final String hash;
  final double lat;
  final double lon;
  final double gpsAccuracy;
  final DateTime capturedAt;
  final double? headingDegrees;
  final double? headingAccuracy;
  final String? headingReference;

  const RemoteLotPhoto({
    required this.role,
    required this.key,
    required this.url,
    required this.hash,
    required this.lat,
    required this.lon,
    required this.gpsAccuracy,
    required this.capturedAt,
    this.headingDegrees,
    this.headingAccuracy,
    this.headingReference,
  });
}

class RemoteTransload {
  final int order;
  final String? plateBefore;
  final String? plateAfter;
  final double? unloadLat;
  final double? unloadLon;
  final double? reloadLat;
  final double? reloadLon;
  final double? distanceMeters;
  final bool compliant;
  final List<RemoteLotPhoto> unloadPhotos;
  final List<RemoteLotPhoto> reloadPhotos;

  const RemoteTransload({
    required this.order,
    required this.plateBefore,
    required this.plateAfter,
    required this.unloadLat,
    required this.unloadLon,
    required this.reloadLat,
    required this.reloadLon,
    required this.distanceMeters,
    required this.compliant,
    this.unloadPhotos = const [],
    this.reloadPhotos = const [],
  });
}

class RemoteLotArrival {
  final String driver;
  final String licenseNumber;
  final double lat;
  final double lon;
  final String gpsStatus;
  final String? plate;
  final bool plateConsistent;
  final int? score;
  final String? licensePhotoUrl;
  final List<RemoteLotPhoto> unloadPhotos;

  const RemoteLotArrival({
    required this.driver,
    required this.licenseNumber,
    required this.lat,
    required this.lon,
    required this.gpsStatus,
    required this.plate,
    required this.plateConsistent,
    required this.score,
    required this.licensePhotoUrl,
    this.unloadPhotos = const [],
  });
}

class RemoteTrackPoint {
  final double lat;
  final double lon;
  final DateTime capturedAt;

  const RemoteTrackPoint({
    required this.lat,
    required this.lon,
    required this.capturedAt,
  });
}

/// Vue utile du payload renvoyé par `GET /api/tracking/lots`.
///
/// Le backend renvoie le même objet que `payload` dans le submit, enrichi de
/// la référence et de la décision de validation. La projection conserve les
/// données nécessaires à la liste, au détail et à leur consultation en cache ;
/// les champs supplémentaires restent volontairement tolérés par le parseur.
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
  final int photoSchemaVersion;
  final String? minePlate;
  final double? mineLat;
  final double? mineLon;
  final double? mineGpsAccuracy;
  final DateTime? mineCapturedAt;
  final List<RemoteLotPhoto> minePhotos;
  final List<RemoteTransload> transloads;
  final RemoteLotArrival? arrival;
  final List<RemoteTrackPoint> track;

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
    this.photoSchemaVersion = 3,
    this.minePlate,
    this.mineLat,
    this.mineLon,
    this.mineGpsAccuracy,
    this.mineCapturedAt,
    this.minePhotos = const [],
    this.transloads = const [],
    this.arrival,
    this.track = const [],
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

  /// Pull du référentiel communes (liste des communes autorisées/actives).
  Future<List<RemoteCommune>> fetchCommunes() async => const [];

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
