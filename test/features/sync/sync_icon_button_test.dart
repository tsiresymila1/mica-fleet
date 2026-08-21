import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/sync/presentation/sync_provider.dart';
import 'package:mica_fleet/features/sync/presentation/widgets/sync_icon_button.dart';

class _InitiallySyncingActivity extends SyncActivityController {
  @override
  bool build() => true;
}

void main() {
  testWidgets('tourne pendant la synchronisation puis se réactive', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        syncInProgressProvider.overrideWith(_InitiallySyncingActivity.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [SyncIconButton(onPressed: () async {})]),
          ),
        ),
      ),
    );
    await tester.pump();

    final buttonFinder = find.descendant(
      of: find.byType(SyncIconButton),
      matching: find.byType(IconButton),
    );
    final rotationFinder = find.descendant(
      of: find.byType(SyncIconButton),
      matching: find.byType(RotationTransition),
    );
    final buttonWhileSyncing = tester.widget<IconButton>(buttonFinder);
    final rotation = tester.widget<RotationTransition>(rotationFinder);
    final before = rotation.turns.value;
    expect(buttonWhileSyncing.onPressed, isNull);

    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, isNot(equals(before)));

    container.read(syncInProgressProvider.notifier).stop();
    await tester.pump();

    final buttonAfterSync = tester.widget<IconButton>(buttonFinder);
    expect(buttonAfterSync.onPressed, isNotNull);
    expect(rotation.turns.value, 0);
  });
}
