import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mica_fleet/core/error/failure.dart';
import 'package:mica_fleet/features/transport/domain/entities/transbordement.dart';
import 'package:mica_fleet/features/transport/domain/repositories/transport_repository.dart';
import 'package:mica_fleet/features/transport/presentation/providers/transport_provider.dart';
import 'package:mica_fleet/features/transport/presentation/screens/transbordement_screen.dart';

class _FakeTransportRepository implements TransportRepository {
  @override
  Future<List<Transbordement>> chaineFor(String lotId) async => const [];

  @override
  Future<int> photoSchemaVersionForLot(String lotId) async => 3;

  @override
  Future<Either<Failure, Unit>> persistChaine(
    String lotId,
    List<Transbordement> chaine,
  ) async => right(unit);
}

void main() {
  testWidgets(
    'affiche la progression des photos de déchargement et rechargement',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transportRepoProvider.overrideWithValue(_FakeTransportRepository()),
          ],
          child: const MaterialApp(home: TransbordementScreen(lotId: 'LOT-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Le déchargement — 0/2'), findsOneWidget);
      expect(find.text('Le rechargement — 0/2'), findsOneWidget);
      final progresses = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(progresses, hasLength(2));
      expect(progresses.map((progress) => progress.value), [0, 0]);
    },
  );
}
