import '../domain/entities/sync_operation.dart';
import '../domain/repositories/remote_data_source.dart';

/// Faux backend pour la démo offline : accepte tout, renvoie un référentiel
/// mines factice. Permet de tester le flux de synchronisation sans Odoo réel.
class MockRemoteDataSource implements RemoteDataSource {
  final List<SyncOperation> recus = [];
  final List<RemoteMine> _validatedSubmissions = [];
  int _seq = 1000;

  @override
  Future<int?> pushOperation(SyncOperation op) async {
    recus.add(op); // accepté (idempotent côté serveur réel via opId)
    final id = ++_seq;
    if (op.entityType == 'mine_submission') {
      _validatedSubmissions.add(
        RemoteMine(
          '$id',
          op.payload['name']?.toString() ?? 'Mine proposée (démo)',
          -18.91,
          47.52,
          20,
          null,
          null,
          null,
          true,
        ),
      );
    }
    return id; // faux odoo_id
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
    ..._validatedSubmissions,
  ];

  @override
  Future<List<RemoteCommune>> fetchCommunes() async => const [
    RemoteCommune(id: 24091, name: 'Andilana', district: 'Ambohidratrimo', actif: true),
    RemoteCommune(id: 24092, name: 'Ambatomena', district: 'Manjakandriana', actif: true),
    RemoteCommune(id: 24093, name: 'Sahatany', district: 'Antsirabe II', actif: true),
  ];

  @override
  Future<List<RemoteDepot>> fetchDepots() async => const [
    RemoteDepot('D001', 'Dépôt Antananarivo', -18.879, 47.5079, 20, true),
    RemoteDepot('D002', 'Dépôt Antsirabe', -19.8659, 47.0334, 20, true),
  ];

  @override
  Future<List<RemoteLot>> fetchLots() async => const [];

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
}
