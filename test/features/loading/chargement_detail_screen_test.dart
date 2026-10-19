import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargement_detail_provider.dart';
import 'package:mica_fleet/features/loading/presentation/screens/chargement_detail_screen.dart';
import 'package:mica_fleet/features/trip/presentation/trip_provider.dart';

void main() {
  testWidgets('affiche les détails complets provenant du GET lots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detail = LotDetail(
      id: 'REMOTE-payload-1',
      sessionId: 'REMOTE-rakoto-session-1',
      displaySessionId: 'session-1',
      mineId: '15',
      mineName: 'Mine serveur',
      reference: 'MINE-15',
      plaqueDepart: '1234 TBR',
      photoPath: null,
      quantite: 420,
      lat: -18.91,
      lon: 47.52,
      date: DateTime.utc(2026, 8, 18, 11, 3),
      statut: 'arrive',
      score: 80,
      minePhotos: const [],
      transbordements: const [
        TransLine(
          1,
          '1234 TBR',
          '5678 TBE',
          true,
          null,
          null,
          [],
          [],
          14.5,
          -18.91,
          47.52,
          -18.90,
          47.53,
        ),
      ],
      arrivee: const ArriveeLine(
        null,
        'Rabe',
        'PERMIS-1',
        'TT/2026/00017',
        'pending_server',
        '5678 TBE',
        true,
        80,
        null,
        null,
        [],
        -18.879,
        47.508,
      ),
      sync: SyncEtat.synchronise,
      validationStatus: 'validated',
      validationReason: null,
      serverReference: 'TT/2026/00017',
      remoteOnly: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lotDetailProvider(
            'REMOTE-payload-1',
          ).overrideWith((ref) async => detail),
          trajetPointsProvider('REMOTE-rakoto-session-1').overrideWith(
            (ref) => Stream.value(const [
              LatLng(-18.91, 47.52),
              LatLng(-18.879, 47.508),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: ChargementDetailScreen(lotId: 'REMOTE-payload-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('session-1'), findsNothing);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Mine serveur'), findsWidgets);
    expect(find.text('Réf. mine : MINE-15'), findsOneWidget);
    expect(find.text('Distance : 14.5 m'), findsOneWidget);
    expect(find.text('-18.87900, 47.50800'), findsNothing);
    expect(find.text('TT/2026/00017'), findsWidgets);
    expect(find.byKey(const ValueKey('route-start-marker')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-end-marker')), findsOneWidget);
    for (final key in ['route-start-marker', 'route-end-marker']) {
      final marker = find.byKey(ValueKey(key));
      expect(
        find.descendant(of: marker, matching: find.byIcon(Icons.location_on)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: marker, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('route-start-marker')),
        matching: find.text('Départ'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('route-end-marker')),
        matching: find.text('Arrivée'),
      ),
      findsOneWidget,
    );
  });
}
