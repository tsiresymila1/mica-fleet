abstract interface class UpdateReadinessRepository {
  /// Nombre de données locales qui pourraient être perdues si l'utilisateur
  /// remplaçait l'application avant leur envoi complet.
  Future<int> unsyncedDataCount();
}
