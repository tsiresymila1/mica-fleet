import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mica_fleet/core/error/failure.dart';
import 'package:mica_fleet/features/depot/domain/entities/arrivee_depot.dart';
import 'package:mica_fleet/features/depot/domain/entities/depot.dart';
import 'package:mica_fleet/features/depot/domain/repositories/depot_repository.dart';
import 'package:mica_fleet/features/depot/presentation/providers/depot_provider.dart';
import 'package:mica_fleet/features/depot/presentation/screens/arrivee_screen.dart';

class _FakeDepotRepository implements DepotRepository {
  final List<Depot> depots;

  const _FakeDepotRepository(this.depots);

  @override
  Future<List<Depot>> activeDepots() async => depots;

  @override
  Future<int> photoSchemaVersionForLot(String lotId) async => 2;

  @override
  Future<LotResume?> lotResume(String lotId) async => null;

  @override
  Future<List<({String id, String mineId, String? couleur})>> lotsEnCours(
    String sessionId,
  ) async => const [];

  @override
  Future<Either<Failure, Unit>> persistArrivee(ArriveeDepot arrivee) async =>
      right(unit);
}

void main() {
  testWidgets('permet de rechercher et sélectionner un dépôt hors ligne', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const depots = [
      Depot(id: 'D1', nom: 'Dépôt Nord', lat: -18.9, lon: 47.5),
      Depot(id: 'D2', nom: 'Dépôt Sud', lat: -19.0, lon: 47.6),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          depotRepoProvider.overrideWithValue(
            const _FakeDepotRepository(depots),
          ),
        ],
        child: const MaterialApp(home: ArriveeScreen(lotId: 'LOT-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choisir le dépôt'), findsOneWidget);
    await tester.tap(find.text('Choisir le dépôt'));
    await tester.pumpAndSettle();

    expect(find.text('Sélectionner un dépôt'), findsOneWidget);
    expect(find.text('Rechercher un dépôt'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Rechercher un dépôt'),
      'Sud',
    );
    await tester.pump();
    expect(find.text('Dépôt Nord'), findsNothing);
    expect(find.text('Dépôt Sud'), findsOneWidget);

    await tester.tap(find.text('Dépôt Sud'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sélection manuelle — le GPS sera vérifié après la photo'),
      findsOneWidget,
    );
  });
}
