import 'package:drift/drift.dart';
import '../../../../core/db/app_database.dart';

class AuthLocalDataSource {
  final AppDatabase db;
  AuthLocalDataSource(this.db);

  Future<FournisseurRow?> findById(String id) => (db.select(
    db.fournisseurs,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> setActiveSession(String id, String nom) async {
    await db.transaction(() async {
      await (db.update(db.fournisseurs)
            ..where((t) => t.id.equals(id).not()))
          .write(const FournisseursCompanion(sessionToken: Value(null)));
      await db.into(db.fournisseurs).insertOnConflictUpdate(
        FournisseursCompanion.insert(
          id: id,
          nom: nom,
          sessionToken: const Value('local'),
        ),
      );
    });
  }

  Future<void> clearActiveSession() async {
    await (db.update(db.fournisseurs)..where((t) => t.sessionToken.isNotNull()))
        .write(const FournisseursCompanion(sessionToken: Value(null)));
  }
}
