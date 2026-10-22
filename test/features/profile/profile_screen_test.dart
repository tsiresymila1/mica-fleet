import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/core/theme/app_theme.dart';
import 'package:mica_fleet/features/auth/data/password_secret_store.dart';
import 'package:mica_fleet/features/auth/domain/entities/fournisseur.dart';
import 'package:mica_fleet/features/auth/presentation/providers/auth_provider.dart';
import 'package:mica_fleet/features/depot/presentation/providers/depot_provider.dart';
import 'package:mica_fleet/features/mines/domain/entities/mine.dart';
import 'package:mica_fleet/features/mines/domain/entities/mine_submission.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mine_submissions_provider.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mines_provider.dart';
import 'package:mica_fleet/features/profile/presentation/screens/profile_screen.dart';
import 'package:mica_fleet/features/sync/domain/entities/sync_operation.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';

class _NoPasswordSecretStore extends PasswordSecretStore {
  @override
  Future<PendingPasswordChange?> pending() async => null;
}

class _SignedInAuthController extends AuthController {
  @override
  Fournisseur? build() => const Fournisseur(id: 'eddy', nom: 'Eddy');
}

class _ReferencesRemote implements RemoteDataSource {
  int minesFetchCount = 0;
  int depotsFetchCount = 0;

  @override
  Future<List<RemoteMine>> fetchMines() async {
    minesFetchCount++;
    return [
      RemoteMine(
        '7',
        'Mine synchronisée',
        -18.9,
        47.5,
        20,
        null,
        null,
        null,
        true,
        reference: 'REF-MINE-7',
        note: 'Note remplacée par le tracking',
        createdAt: DateTime.utc(2026, 8, 14, 7, 30),
        fokontany: 'Andilana',
      ),
    ];
  }

  @override
  Future<List<RemoteDepot>> fetchDepots() async {
    depotsFetchCount++;
    return const [RemoteDepot('8', 'Dépôt synchronisé', -18.8, 47.4, 20, true)];
  }

  @override
  Future<List<RemoteLot>> fetchLots() async => [
    RemoteLot(
      payloadId: 'payload-lot-7',
      sessionId: 'session-lot-7',
      reference: 'MICA-2026-0042',
      validationStatus: 'validated',
      validationReason: null,
      createdAt: DateTime.utc(2026, 8, 14, 8),
      updatedAt: DateTime.utc(2026, 8, 14, 10),
      mineId: '7',
      mineName: 'Mine synchronisée',
      mineReference: 'REF-MINE-7',
      mineNote: 'Note du backend tracking',
      estimatedQuantity: 120,
      transportStatus: 'arrive',
      score: 96,
    ),
  ];

  @override
  Future<List<RemoteCommune>> fetchCommunes() async => const [];

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<int?> pushOperation(SyncOperation op) async => null;

  @override
  Future<void> uploadMinePhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {}

  @override
  Future<void> uploadPhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {}
}

void main() {
  testWidgets(
    'le pull-to-refresh synchronise les mines et les dépôts depuis le serveur',
    (tester) async {
      tester.view.physicalSize = const Size(430, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase.memory();
      final remote = _ReferencesRemote();
      addTearDown(db.close);
      await db
          .into(db.fournisseurs)
          .insert(
            FournisseursCompanion.insert(
              id: 'eddy',
              nom: 'Eddy',
              sessionToken: const Value('token'),
            ),
          );
      final container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          remoteDataSourceProvider.overrideWithValue(remote),
          passwordSecretStoreProvider.overrideWithValue(
            _NoPasswordSecretStore(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SitesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucune mine trouvée'), findsOneWidget);
      expect(remote.minesFetchCount, 0);
      expect(remote.depotsFetchCount, 0);

      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refreshIndicator.onRefresh();

      expect(remote.minesFetchCount, 1);
      expect(remote.depotsFetchCount, 1);
      expect((await db.select(db.mines).get()).single.nom, 'Mine synchronisée');
      expect(
        (await db.select(db.depots).get()).single.nom,
        'Dépôt synchronisé',
      );
      await tester.pumpAndSettle();

      expect(find.text('RÉFÉRENCE'), findsOneWidget);
      expect(find.text('REF-MINE-7'), findsOneWidget);
      expect(find.text('14/08/2026'), findsOneWidget);
      expect(find.text('Note du backend tracking'), findsOneWidget);
      expect(find.textContaining('GPS -18.90000'), findsNothing);
      expect(find.text('LOCALISATION'), findsOneWidget);
      expect(find.text('Andilana'), findsOneWidget);
      expect(find.text('Synchronisée'), findsOneWidget);
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('site-status-7')))
            .color,
        AppColors.ok,
      );
      expect(
        tester.widget<Material>(find.byKey(const ValueKey('site-7'))).shape,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Andilana');
      await tester.pumpAndSettle();
      expect(find.text('Mine synchronisée'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Inconnue');
      await tester.pumpAndSettle();
      expect(find.text('Aucune mine trouvée'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mine synchronisée'));
      await tester.pumpAndSettle();

      expect(find.text('Lots rattachés à Mine synchronisée'), findsOneWidget);
      expect(find.text('MICA-2026-0042'), findsOneWidget);
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Dépôts ('));
      await tester.pumpAndSettle();
      expect(find.text('Dépôt synchronisé'), findsOneWidget);
      expect(
        tester.widget<Material>(find.byKey(const ValueKey('site-8'))).shape,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '8');
      await tester.pumpAndSettle();
      expect(find.text('Dépôt synchronisé'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Autre');
      await tester.pumpAndSettle();
      expect(find.text('Aucun dépôt trouvé'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('distingue les mines du serveur des propositions locales', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          minesProvider.overrideWith(
            (ref) async => const [
              Mine(id: '7', nom: 'Mine serveur', lat: -18.9, lon: 47.5),
            ],
          ),
          mineSubmissionsProvider.overrideWith(
            (ref) async => [
              MineSubmission(
                payloadId: 'local-1',
                deviceUuid: 'device-1',
                nom: 'Mine locale',
                state: MineSubmissionState.localPending,
                createdAt: DateTime.utc(2026, 10, 21),
                updatedAt: DateTime.utc(2026, 10, 21),
                photos: const [],
              ),
            ],
          ),
          activeDepotsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: SitesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mine serveur'), findsOneWidget);
    expect(find.text('Mine locale'), findsOneWidget);
    expect(find.text('Synchronisée'), findsOneWidget);
    expect(find.text('À synchroniser'), findsOneWidget);
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('site-status-7')))
          .color,
      AppColors.ok,
    );
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('site-status-local-local-1')),
          )
          .color,
      AppColors.warn,
    );

    await tester.enterText(find.byType(TextField), 'locale');
    await tester.pumpAndSettle();
    expect(find.text('Mine locale'), findsOneWidget);
    expect(find.text('Mine serveur'), findsNothing);
  });
}
