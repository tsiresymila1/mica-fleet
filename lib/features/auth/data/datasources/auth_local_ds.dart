import 'package:drift/drift.dart';
import '../../../../core/db/app_database.dart';

class AuthLocalDataSource {
  final AppDatabase db;
  AuthLocalDataSource(this.db);

  Future<FournisseurRow?> findById(String id) =>
      (db.select(db.fournisseurs)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> saveSession(String id, String nom) =>
      db.into(db.fournisseurs).insertOnConflictUpdate(
            FournisseursCompanion.insert(
                id: id, nom: nom, sessionToken: const Value('local')),
          );
}
