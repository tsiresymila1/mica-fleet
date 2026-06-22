import '../entities/sync_operation.dart';

class RemoteMine {
  final String id, nom;
  final double lat, lon, rayonMetres;
  final String? district, commune, region;
  final bool actif;
  RemoteMine(this.id, this.nom, this.lat, this.lon, this.rayonMetres,
      this.district, this.commune, this.region, this.actif);
}

abstract class RemoteDataSource {
  /// Push idempotent : Odoo déduplique sur op.opId. Lève en cas d'échec réseau.
  Future<void> pushOperation(SyncOperation op);

  /// Pull du référentiel mines.
  Future<List<RemoteMine>> fetchMines();
}
