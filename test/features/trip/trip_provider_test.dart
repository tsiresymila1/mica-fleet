import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/trip/presentation/trip_provider.dart';

void main() {
  test(
    'le provider de carte reçoit les nouveaux points locaux sans refetch',
    () async {
      final db = AppDatabase.memory();
      await db
          .into(db.chargements)
          .insert(
            ChargementsCompanion.insert(
              id: 'C1',
              fournisseurId: 'agent',
              dateCreation: DateTime.now(),
            ),
          );
      final container = ProviderContainer(
        overrides: [dbProvider.overrideWithValue(db)],
      );
      final updated = Completer<List<LatLng>>();
      final subscription = container.listen(trajetPointsProvider('C1'), (
        _,
        value,
      ) {
        final points = value.asData?.value;
        if (points != null && points.isNotEmpty && !updated.isCompleted) {
          updated.complete(points);
        }
      });
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await db.close();
      });
      expect(await container.read(trajetPointsProvider('C1').future), isEmpty);
      await db
          .into(db.trajetPoints)
          .insert(
            TrajetPointsCompanion.insert(
              chargementId: 'C1',
              lat: -18.9,
              lon: 47.5,
              capturedAt: DateTime.now(),
            ),
          );
      final points = await updated.future.timeout(const Duration(seconds: 2));
      expect(points.single, const LatLng(-18.9, 47.5));
    },
  );
}
