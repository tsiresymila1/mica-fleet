import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/di/providers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/mine.dart';

/// Liste des mines actives du référentiel local (synchronisé depuis Odoo).
final minesProvider = FutureProvider<List<Mine>>((ref) async {
  final db = ref.watch(dbProvider);
  final agentLogin = ref.watch(authControllerProvider)?.id;
  final allRows = await db.select(db.mines).get();
  final allSubmissions = await db.select(db.mineSubmissions).get();
  final submissions = agentLogin == null
      ? const <MineSubmissionRow>[]
      : allSubmissions
            .where((submission) => submission.agentLogin == agentLogin)
            .toList();
  final localPayloadIds = submissions
      .map((submission) => submission.payloadId)
      .toSet();
  final localRowsById = {for (final row in allRows) row.id: row};

  final mines = allRows
      .where((row) => row.actif && !localPayloadIds.contains(row.id))
      .map(_mineFromRow)
      .toList();
  final visibleIds = mines.map((mine) => mine.id).toSet();

  // POST /api/mine fournit déjà un id Odoo alors que GET /api/mine peut ne
  // retourner que les mines validées. Entre ces deux étapes, on expose une
  // vue canonique portant l'id serveur et les métadonnées locales disponibles.
  for (final submission in submissions) {
    final serverId = submission.serverId?.toString();
    if (serverId == null ||
        submission.state == 'rejected' ||
        visibleIds.contains(serverId)) {
      continue;
    }
    final local = localRowsById[submission.payloadId];
    mines.add(
      Mine(
        id: serverId,
        nom: submission.nom,
        lat: local?.lat ?? 0,
        lon: local?.lon ?? 0,
        rayonMetres: local?.rayonMetres ?? 0,
        reference: local?.reference,
        note: local?.note,
        createdAt: local?.createdAt ?? submission.createdAt,
        district: local?.district,
        fokontany: local?.fokontany,
        commune: local?.commune,
        region: local?.region,
      ),
    );
    visibleIds.add(serverId);
  }
  mines.sort(_compareMineCreatedAtDescending);
  return mines;
});

int _compareMineCreatedAtDescending(Mine first, Mine second) {
  final firstDate = first.createdAt;
  final secondDate = second.createdAt;
  if (firstDate == null && secondDate == null) {
    return first.nom.compareTo(second.nom);
  }
  if (firstDate == null) return 1;
  if (secondDate == null) return -1;

  final byDate = secondDate.compareTo(firstDate);
  return byDate != 0 ? byDate : first.nom.compareTo(second.nom);
}

Mine _mineFromRow(MineRow row) => Mine(
  id: row.id,
  nom: row.nom,
  lat: row.lat,
  lon: row.lon,
  rayonMetres: row.rayonMetres,
  reference: row.reference,
  note: row.note,
  createdAt: row.createdAt,
  district: row.district,
  fokontany: row.fokontany,
  commune: row.commune,
  region: row.region,
  actif: row.actif,
);
