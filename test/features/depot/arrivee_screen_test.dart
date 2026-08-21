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
  Future<int> photoSchemaVersionForLot(String lotId) async => 3;

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
  testWidgets('ne demande plus le dépôt et affiche les deux photos v3', (
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

    expect(find.textContaining('Choisir le dépôt'), findsNothing);
    expect(find.text('Photos du déchargement — 0/2'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0);
    expect(find.text('Photo de la plaque'), findsOneWidget);
    expect(find.text('Photo du mica'), findsNothing);
    expect(find.text('Photo du camion avec mica'), findsOneWidget);
    expect(find.textContaining('déterminés par le serveur'), findsOneWidget);
  });
}
