import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/core/update/app_update_service.dart';
import 'package:mica_fleet/features/update/domain/update_readiness_repository.dart';
import 'package:mica_fleet/features/update/presentation/app_update_provider.dart';
import 'package:mica_fleet/features/update/presentation/app_update_ui.dart';

void main() {
  testWidgets('affiche une petite bannière pour une mise à jour obligatoire', (
    tester,
  ) async {
    const check = AppUpdateCheck(
      currentVersion: '1.2.6',
      currentBuild: 114,
      update: AppUpdateInfo(
        version: '1.2.7',
        build: 115,
        apkUrl: 'https://example.test/app.apk',
        sha256Hash: 'abc',
        mandatory: true,
        releaseNotes: 'Correctifs',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateControllerProvider.overrideWith(
            () => _FixedUpdateController(check),
          ),
        ],
        child: const MaterialApp(
          home: AppUpdateBanner(child: Scaffold(body: Text('Accueil'))),
        ),
      ),
    );

    expect(
      find.text('Mise à jour obligatoire 1.2.7 disponible'),
      findsOneWidget,
    );
    expect(find.text('Mettre à jour'), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
  });

  testWidgets('affiche la progression dans une feuille modale', (tester) async {
    const update = AppUpdateInfo(
      version: '1.2.7',
      build: 115,
      apkUrl: 'https://example.test/app.apk',
      sha256Hash: 'abc',
      mandatory: false,
      releaseNotes: 'Correctifs',
    );
    const check = AppUpdateCheck(
      currentVersion: '1.2.6',
      currentBuild: 114,
      update: update,
    );
    final gateway = _ProgressUpdateGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateControllerProvider.overrideWith(
            () => _FixedUpdateController(check),
          ),
          appUpdateServiceProvider.overrideWithValue(gateway),
          updateReadinessRepositoryProvider.overrideWithValue(
            const _NoPendingData(),
          ),
        ],
        child: const MaterialApp(
          home: AppUpdateBanner(child: Scaffold(body: Text('Accueil'))),
        ),
      ),
    );

    await tester.tap(find.text('Mettre à jour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Télécharger'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Téléchargement de la mise à jour'), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);

    gateway.complete();
    await tester.pumpAndSettle();
    expect(find.text('Téléchargement de la mise à jour'), findsNothing);
  });
}

class _FixedUpdateController extends AppUpdateController {
  final AppUpdateCheck checkValue;

  _FixedUpdateController(this.checkValue);

  @override
  AppUpdateState build() => AppUpdateState(check: checkValue);
}

class _NoPendingData implements UpdateReadinessRepository {
  const _NoPendingData();

  @override
  Future<int> unsyncedDataCount() async => 0;
}

class _ProgressUpdateGateway implements AppUpdateGateway {
  final _completion = Completer<String>();

  void complete() => _completion.complete('installer_opened');

  @override
  Future<AppUpdateCheck> check() async => throw UnimplementedError();

  @override
  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) {
    onProgress?.call(50, 100);
    return _completion.future;
  }
}
