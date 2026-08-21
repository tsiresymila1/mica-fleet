import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/core/di/providers.dart';
import 'package:mica_fleet/features/auth/domain/entities/fournisseur.dart';
import 'package:mica_fleet/features/auth/presentation/providers/auth_provider.dart';
import 'package:mica_fleet/features/mines/data/repositories/mine_submission_repository_impl.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mine_submissions_provider.dart';
import 'package:mica_fleet/features/mines/presentation/providers/mines_provider.dart';

class _SignedInAuthController extends AuthController {
  @override
  Fournisseur? build() => const Fournisseur(id: 'eddy', nom: 'Eddy');
}

void main() {
  test(
    'préfère la mine serveur et masque sa proposition locale approuvée',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final now = DateTime.utc(2026, 8, 21);

      await db.batch((batch) {
        batch.insert(
          db.mines,
          MinesCompanion.insert(
            id: 'local-payload-uuid',
            nom: 'Nom local',
            lat: -18.9,
            lon: 47.5,
            actif: const Value(true),
          ),
        );
        batch.insert(
          db.mines,
          MinesCompanion.insert(
            id: '42',
            nom: 'Nom canonique Odoo',
            lat: -18.91,
            lon: 47.52,
            reference: const Value('REF-42'),
            actif: const Value(true),
          ),
        );
        batch.insert(
          db.mineSubmissions,
          MineSubmissionsCompanion.insert(
            payloadId: 'local-payload-uuid',
            deviceUuid: 'local-device-uuid',
            nom: 'Nom local',
            agentLogin: const Value('eddy'),
            state: const Value('approved'),
            serverId: const Value(42),
            approvedMineId: const Value('42'),
            createdAt: now,
            updatedAt: now,
          ),
        );
      });

      final container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
      );
      addTearDown(container.dispose);

      final mines = await container.read(minesProvider.future);
      final submissions = await container.read(mineSubmissionsProvider.future);

      expect(mines.map((mine) => mine.id), ['42']);
      expect(mines.single.nom, 'Nom canonique Odoo');
      expect(submissions, isEmpty);
    },
  );

  test(
    'conserve la mine serveur après suppression locale avant validation',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final now = DateTime.utc(2026, 8, 21);

      await db.batch((batch) {
        batch.insert(
          db.mines,
          MinesCompanion.insert(
            id: 'pending-local-payload',
            nom: 'Mine déjà envoyée',
            lat: -18.9,
            lon: 47.5,
            createdAt: Value(now),
            actif: const Value(false),
          ),
        );
        batch.insert(
          db.mineSubmissions,
          MineSubmissionsCompanion.insert(
            payloadId: 'pending-local-payload',
            deviceUuid: 'pending-local-device',
            nom: 'Mine déjà envoyée',
            agentLogin: const Value('eddy'),
            state: const Value('pending_validation'),
            serverId: const Value(77),
            createdAt: now,
            updatedAt: now,
          ),
        );
      });

      final container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
      );
      addTearDown(container.dispose);

      expect((await container.read(minesProvider.future)).single.id, '77');
      expect(
        await container.read(mineSubmissionsProvider.future),
        hasLength(1),
      );

      final deleted = await MineSubmissionRepositoryImpl(
        db,
      ).delete('pending-local-payload');
      container.invalidate(minesProvider);
      container.invalidate(mineSubmissionsProvider);

      expect(deleted.isRight(), isTrue);
      expect((await container.read(minesProvider.future)).single.id, '77');
      expect(await container.read(mineSubmissionsProvider.future), isEmpty);
      expect(
        (await db.select(db.mineSubmissions).get()).single.state,
        'hidden',
      );

      // Un GET /api/mine vide désactive le cache distant, mais ne doit pas
      // faire disparaître l'id serveur déjà obtenu par POST /api/mine.
      await db
          .update(db.mines)
          .write(const MinesCompanion(actif: Value(false)));
      container.invalidate(minesProvider);
      expect((await container.read(minesProvider.future)).single.id, '77');
    },
  );

  test(
    'trie les mines du référentiel de la plus récente à la plus ancienne',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);

      await db.batch((batch) {
        batch.insert(
          db.mines,
          MinesCompanion.insert(
            id: 'older',
            nom: 'Mine ancienne',
            lat: -18.9,
            lon: 47.5,
            createdAt: Value(DateTime.utc(2026, 8, 10)),
          ),
        );
        batch.insert(
          db.mines,
          MinesCompanion.insert(
            id: 'without-date',
            nom: 'Mine sans date',
            lat: -18.9,
            lon: 47.5,
          ),
        );
        batch.insert(
          db.mines,
          MinesCompanion.insert(
            id: 'newer',
            nom: 'Mine récente',
            lat: -18.9,
            lon: 47.5,
            createdAt: Value(DateTime.utc(2026, 8, 20)),
          ),
        );
      });

      final container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
      );
      addTearDown(container.dispose);

      final mines = await container.read(minesProvider.future);

      expect(mines.map((mine) => mine.id), ['newer', 'older', 'without-date']);
    },
  );

  test(
    'trie les propositions de mine de la plus récente à la plus ancienne',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final older = DateTime.utc(2026, 8, 10);
      final newer = DateTime.utc(2026, 8, 20);

      await db.batch((batch) {
        batch.insert(
          db.mineSubmissions,
          MineSubmissionsCompanion.insert(
            payloadId: 'older',
            deviceUuid: 'device-older',
            nom: 'Proposition ancienne',
            agentLogin: const Value('eddy'),
            createdAt: older,
            updatedAt: older,
          ),
        );
        batch.insert(
          db.mineSubmissions,
          MineSubmissionsCompanion.insert(
            payloadId: 'newer',
            deviceUuid: 'device-newer',
            nom: 'Proposition récente',
            agentLogin: const Value('eddy'),
            createdAt: newer,
            updatedAt: newer,
          ),
        );
      });

      final container = ProviderContainer(
        overrides: [
          dbProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
      );
      addTearDown(container.dispose);

      final submissions = await container.read(mineSubmissionsProvider.future);

      expect(submissions.map((submission) => submission.payloadId), [
        'newer',
        'older',
      ]);
    },
  );
}
