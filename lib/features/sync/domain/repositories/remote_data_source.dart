import '../entities/sync_operation.dart';

class RemoteMine {
  final String id, nom;
  final double lat, lon, rayonMetres;
  final String? district, commune, region;
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
    this.actif,
  );
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

class RemoteCommune {
  final int id;
  final String nom;
  final String? district;
  final bool actif;

  const RemoteCommune(this.id, this.nom, this.district, this.actif);
}

/// Une photo à uploader : clé (slot), fichier local, hash (idempotence).
class PhotoPart {
  final String key;
  final String path;
  final String hash;
  PhotoPart(this.key, this.path, this.hash);
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

  /// Pull du référentiel communes.
  Future<List<RemoteCommune>> fetchCommunes();
}
