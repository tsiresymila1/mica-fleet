import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargement_detail_provider.dart';
import 'package:mica_fleet/features/loading/presentation/providers/chargements_list_provider.dart';
import 'package:mica_fleet/features/loading/presentation/screens/home_screen.dart';

void main() {
  testWidgets('place le filtre Tous après les statuts métier', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
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
                couleur: 'Blanc',
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
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final pendingX = tester.getTopLeft(find.text('En attente')).dx;
    final validatedX = tester.getTopLeft(find.text('Validés')).dx;
    final rejectedX = tester.getTopLeft(find.text('Rejetés')).dx;
    final allX = tester.getTopLeft(find.text('Tous')).dx;

    expect(pendingX, lessThan(validatedX));
    expect(validatedX, lessThan(rejectedX));
    expect(rejectedX, lessThan(allX));
  });
}
