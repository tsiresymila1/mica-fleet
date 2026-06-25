import 'package:drift/drift.dart';
import 'app_database.dart';

/// Insère des données de démonstration (fournisseur, mines, dépôts) si la base
/// est vide. Idempotent. À n'utiliser qu'en développement / démo offline.
class DevSeeder {
  final AppDatabase db;
  DevSeeder(this.db);

  Future<void> seedIfEmpty() async {
    final existing = await db.select(db.fournisseurs).get();
    if (existing.isNotEmpty) return;

    await db.into(db.fournisseurs).insert(FournisseursCompanion.insert(
        id: 'F001', nom: 'Fournisseur Démo'));

    const mines = [
      ('M001', 'Carrière Andilana', -18.91000, 47.52000, 'Ambohidratrimo', 'Andilana', 'Analamanga'),
      ('M002', 'Carrière Ambatomena', -18.92500, 47.53500, 'Manjakandriana', 'Ambatomena', 'Analamanga'),
      ('M003', 'Carrière Sahatany', -19.00000, 47.60000, 'Antsirabe II', 'Sahatany', 'Vakinankaratra'),
    ];
    for (final (id, nom, lat, lon, district, commune, region) in mines) {
      await db.into(db.mines).insert(MinesCompanion.insert(
          id: id, nom: nom, lat: lat, lon: lon,
          district: Value(district), commune: Value(commune),
          region: Value(region)));
    }

    const depots = [
      ('D001', 'Dépôt Antananarivo', -18.87900, 47.50790),
      ('D002', 'Dépôt Antsirabe', -19.86590, 47.03340),
    ];
    for (final (id, nom, lat, lon) in depots) {
      await db.into(db.depots).insert(DepotsCompanion.insert(
          id: id, nom: nom, lat: lat, lon: lon));
    }
  }
}
