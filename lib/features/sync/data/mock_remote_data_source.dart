import '../domain/entities/sync_operation.dart';
import '../domain/repositories/remote_data_source.dart';

/// Faux backend pour la démo offline : accepte tout, renvoie un référentiel
/// mines factice. Permet de tester le flux de synchronisation sans Odoo réel.
class MockRemoteDataSource implements RemoteDataSource {
  final List<SyncOperation> recus = [];
  int _seq = 1000;

  @override
  Future<int?> pushOperation(SyncOperation op) async {
    recus.add(op); // accepté (idempotent côté serveur réel via opId)
    return ++_seq; // faux odoo_id
  }

  @override
  Future<void> uploadPhotos(
      String deviceUuid, String loadId, List<PhotoPart> photos) async {
    // Démo : accepté sans rien envoyer.
  }

  @override
  Future<List<RemoteMine>> fetchMines() async => [
        RemoteMine('M001', 'Carrière Andilana', -18.91000, 47.52000, 20,
            'Ambohidratrimo', 'Andilana', 'Analamanga', true),
        RemoteMine('M002', 'Carrière Ambatomena', -18.92500, 47.53500, 20,
            'Manjakandriana', 'Ambatomena', 'Analamanga', true),
        RemoteMine('M003', 'Carrière Sahatany', -19.00000, 47.60000, 20,
            'Antsirabe II', 'Sahatany', 'Vakinankaratra', true),
      ];
}
