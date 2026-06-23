import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../domain/entities/mine.dart';

/// Liste des mines actives du référentiel local (synchronisé depuis Odoo).
final minesProvider = FutureProvider<List<Mine>>((ref) async {
  final db = ref.watch(dbProvider);
  final rows = await (db.select(db.mines)..where((m) => m.actif.equals(true)))
      .get();
  return rows
      .map((r) => Mine(
            id: r.id,
            nom: r.nom,
            lat: r.lat,
            lon: r.lon,
            rayonMetres: r.rayonMetres,
            district: r.district,
            commune: r.commune,
            region: r.region,
            actif: r.actif,
          ))
      .toList();
});
