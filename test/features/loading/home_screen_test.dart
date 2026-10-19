import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargement_detail_provider.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargements_list_provider.dart';
import 'package:mica_fleet/features/loading/presentation/screens/home_screen.dart';

void main() {
  testWidgets('filtre les lots et montre les couleurs de validation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lotsListProvider.overrideWith(
            (ref) async => [
              LotListItem(
                id: 'lot-1',
                sessionId: 'session-1',
                mineId: 'mine-1',
                mineName: 'Mine 1',
                tonnage: 120,
                date: DateTime.utc(2026, 8, 21),
                statut: 'arrive',
                score: 96,
                arrive: true,
                sync: SyncEtat.synchronise,
                validationStatus: 'validated',
                validationReason: null,
                serverReference: 'MICA-2026-0042',
                remoteOnly: true,
                plate: '1234 TBR',
              ),
              LotListItem(
                id: 'lot-2',
                sessionId: 'session-2',
                mineId: 'mine-1',
                mineName: 'Mine 1',
                tonnage: 50,
                date: DateTime.utc(2026, 8, 22),
                statut: 'en_cours',
                score: null,
                arrive: false,
                sync: SyncEtat.enAttente,
                validationStatus: 'pending',
                validationReason: null,
                serverReference: null,
                remoteOnly: false,
                plate: '5678 ABC',
              ),
              LotListItem(
                id: 'lot-3',
                sessionId: 'session-3',
                mineId: 'mine-2',
                mineName: 'Mine 2',
                tonnage: 70,
                date: DateTime.utc(2026, 8, 23),
                statut: 'arrive',
                score: null,
                arrive: true,
                sync: SyncEtat.synchronise,
                validationStatus: 'rejected',
                validationReason: 'Photo manquante',
                serverReference: 'MICA-2026-0043',
                remoteOnly: true,
                plate: '9012 TBR',
              ),
              LotListItem(
                id: 'lot-4',
                sessionId: 'session-4',
                mineId: 'mine-2',
                mineName: 'Mine 2',
                tonnage: 80,
                date: DateTime.utc(2026, 8, 24),
                statut: 'en_cours',
                score: null,
                arrive: false,
                sync: SyncEtat.local,
                validationStatus: 'pending',
                validationReason: null,
                serverReference: null,
                remoteOnly: false,
                plate: '3456 ABC',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final allX = tester.getTopLeft(find.text('Tous')).dx;
    final pendingX = tester.getTopLeft(find.text('Attente')).dx;
    final validatedX = tester.getTopLeft(find.text('Validés')).dx;
    final rejectedX = tester.getTopLeft(find.text('Rejetés')).dx;

    expect(allX, lessThan(pendingX));
    expect(pendingX, lessThan(validatedX));
    expect(validatedX, lessThan(rejectedX));
    expect(find.text('1234 TBR'), findsOneWidget);
    expect(find.text('Arrivé'), findsNWidgets(2));
    expect(find.text('96'), findsOneWidget);
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('lot-status-lot-1')))
          .color,
      const Color(0xFF169365),
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('lot-status-lot-2')))
          .color,
      const Color(0xFFD99A28),
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('lot-status-lot-3')))
          .color,
      const Color(0xFFD74858),
    );
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('lot-status-lot-4')))
          .color,
      const Color(0xFF94A3BF),
    );

    await tester.enterText(find.byType(TextField), '5678 ABC');
    await tester.pumpAndSettle();
    expect(find.text('lot-2'), findsOneWidget);
    expect(find.text('MICA-2026-0042'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Validés'));
    await tester.pumpAndSettle();
    expect(find.text('MICA-2026-0042'), findsOneWidget);
    expect(find.text('lot-2'), findsNothing);

    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('OPÉRATIONS'), findsOneWidget);
    expect(find.text('Mes mines et dépôts'), findsOneWidget);
    expect(find.text('DONNÉES ET COMPTE'), findsOneWidget);
    expect(find.text('Aide'), findsOneWidget);
    expect(find.text('Paramètres'), findsNothing);
  });

  testWidgets('garde les filtres et la création visibles sans lot', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [lotsListProvider.overrideWith((ref) async => [])],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aucun lot'), findsOneWidget);
    expect(find.text('Tous'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Nouveau chargement'), findsOneWidget);
  });
}
