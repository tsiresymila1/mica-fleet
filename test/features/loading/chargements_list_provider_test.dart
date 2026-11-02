import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/auth/domain/entities/fournisseur.dart';
import 'package:mica_fleet/features/auth/presentation/providers/auth_provider.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargements_list_provider.dart';

class _SignedInAuthController extends AuthController {
  @override
  Fournisseur? build() => const Fournisseur(id: 'F001', nom: 'Agent');
}

void main() {
  test(
    'résout le dépôt rattaché au lot et laisse les autres sans dépôt',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db
          .into(db.mines)
          .insert(
            MinesCompanion.insert(
              id: 'M1',
              nom: 'Mine 1',
              lat: -18.9,
              lon: 47.5,
            ),
          );
      await db
          .into(db.depots)
          .insert(
            DepotsCompanion.insert(
              id: 'D1',
              nom: 'Dépôt FTU',
              lat: -18.8,
              lon: 47.6,
            ),
          );
      await db
          .into(db.chargements)
          .insert(
            ChargementsCompanion.insert(
              id: 'S1',
              fournisseurId: 'F001',
              dateCreation: DateTime.utc(2026, 10, 28, 7, 15),
            ),
          );
      for (final id in ['L1', 'L2']) {
        await db
            .into(db.lots)
            .insert(
              LotsCompanion.insert(id: id, sessionId: 'S1', mineId: 'M1'),
            );
      }
      await db
          .into(db.arriveesDepot)
          .insert(
            ArriveesDepotCompanion.insert(
              lotId: 'L1',
              depotId: const Value('D1'),
              chauffeur: 'Agent',
              numPermis: 'P1',
              numLot: 'N1',
              gpsLat: -18.8,
              gpsLon: 47.6,
              statutGps: 'valide',
            ),
          );

      final container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
      );
      addTearDown(container.dispose);

      final lots = await container.read(lotsListProvider.future);
      expect(lots.singleWhere((lot) => lot.id == 'L1').depotName, 'Dépôt FTU');
      expect(lots.singleWhere((lot) => lot.id == 'L2').depotName, isNull);
    },
  );
}
