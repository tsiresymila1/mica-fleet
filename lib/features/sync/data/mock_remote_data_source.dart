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
  Future<void> uploadPhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {
    // Démo : accepté sans rien envoyer.
  }

  @override
  Future<void> uploadMinePhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {
    // Démo : accepté sans rien envoyer.
  }

  @override
  Future<RemoteMineSubmissionStatus> fetchMineSubmissionStatus(
    String payloadId,
  ) async => RemoteMineSubmissionStatus(
    payloadId: payloadId,
    state: 'approved',
    mine: RemoteMine(
      'DEMO-${payloadId.substring(0, 8)}',
      'Mine proposée (démo)',
      -18.91,
      47.52,
      20,
      null,
      null,
      null,
      true,
    ),
  );

  @override
  Future<List<RemoteMine>> fetchMines() async => [
    RemoteMine(
      'M001',
      'Carrière Andilana',
      -18.91000,
      47.52000,
      20,
      'Ambohidratrimo',
      'Andilana',
      'Analamanga',
      true,
    ),
    RemoteMine(
      'M002',
      'Carrière Ambatomena',
      -18.92500,
      47.53500,
      20,
      'Manjakandriana',
      'Ambatomena',
      'Analamanga',
      true,
    ),
    RemoteMine(
      'M003',
      'Carrière Sahatany',
      -19.00000,
      47.60000,
      20,
      'Antsirabe II',
      'Sahatany',
      'Vakinankaratra',
      true,
    ),
  ];
}
