import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/capture/domain/entities/captured_photo.dart';
import 'package:mica_fleet/features/mines/data/repositories/mine_submission_repository_impl.dart';
import 'package:uuid/uuid.dart';

CapturedPhoto _photo(int index, Directory directory) {
  final file = File('${directory.path}/mine_position_$index.jpg')
    ..writeAsBytesSync([index]);
  return CapturedPhoto(
    path: file.path,
    sha256: 'hash-$index',
    lat: -18.91 + index / 10000,
    lon: 47.52 + index / 10000,
    precision: 4 + index / 10,
    takenAt: DateTime.utc(2026, 7, 30, 8, index),
    headingDegrees: 40.0 + index,
    headingAccuracy: 2.5,
    headingReference: 'magnetic',
  );
}

void main() {
  late AppDatabase db;
  late MineSubmissionRepositoryImpl repository;
  late Directory storage;

  setUp(() {
    db = AppDatabase.memory();
    storage = Directory.systemTemp.createTempSync('mica_mine_repo_');
    repository = MineSubmissionRepositoryImpl(
      db,
      storageDirectory: () async => storage,
    );
  });

  tearDown(() async {
    await db.close();
    if (storage.existsSync()) storage.deleteSync(recursive: true);
  });

  test('refuse une proposition avec moins de 5 photos', () async {
    final result = await repository.create(
      name: 'Mine test',
      photos: [for (var i = 1; i <= 4; i++) _photo(i, storage)],
      agentLogin: 'eddy',
    );

    expect(result.isLeft(), isTrue);
    expect(await db.select(db.mineSubmissions).get(), isEmpty);
    expect(await db.select(db.syncQueue).get(), isEmpty);
  });

  test('sauvegarde 5 preuves et crée un payload UUID dans la file', () async {
    final result = await repository.create(
      name: '  Mine Antsahabe  ',
      photos: [for (var i = 1; i <= 5; i++) _photo(i, storage)],
      agentLogin: 'eddy',
    );

    expect(result.isRight(), isTrue);
    final submission = (await db.select(db.mineSubmissions).get()).single;
    expect(submission.nom, 'Mine Antsahabe');
    expect(submission.communeId, isNull);
    expect(Uuid.isValidUUID(fromString: submission.payloadId), isTrue);
    expect(Uuid.isValidUUID(fromString: submission.deviceUuid), isTrue);
    expect(submission.state, 'local_pending');
    final localMine = (await db.select(db.mines).get()).single;
    expect(localMine.id, submission.payloadId);
    expect(localMine.nom, 'Mine Antsahabe');
    expect(localMine.actif, isFalse);

    final photos = await db.select(db.mineSubmissionPhotos).get();
    expect(photos, hasLength(5));
    expect(photos.map((p) => p.key), [
      'position_1',
      'position_2',
      'position_3',
      'position_4',
      'position_5',
    ]);

    final queued = (await db.select(db.syncQueue).get()).single;
    expect(queued.opId, submission.deviceUuid);
    expect(queued.entityType, 'mine_submission');
    final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
    expect(payload['id'], submission.payloadId);
    expect(payload['name'], 'Mine Antsahabe');
    expect(payload.containsKey('commune_id'), isFalse);
    expect(payload['positions'], hasLength(5));
    final firstHash = (payload['positions'] as List).first['hash'] as String;
    expect(firstHash, hasLength(64));
    expect(firstHash, photos.first.hash);
    final firstPosition = (payload['positions'] as List).first as Map;
    expect(firstPosition['heading_deg'], 41.0);
    expect(firstPosition['heading_accuracy'], 2.5);
    expect(firstPosition['heading_reference'], 'magnetic');
    expect(photos.first.headingDegrees, 41.0);
    expect(photos.first.headingAccuracy, 2.5);
    expect(photos.first.headingReference, 'magnetic');
    expect(photos.every((photo) => File(photo.path).existsSync()), isTrue);
  });

  test('inclut la commune quand communeId est renseigné', () async {
    final result = await repository.create(
      name: 'Mine avec commune',
      photos: [for (var i = 1; i <= 5; i++) _photo(i, storage)],
      agentLogin: 'eddy',
      communeId: 24091,
    );

    expect(result.isRight(), isTrue);
    final queued = (await db.select(db.syncQueue).get()).single;
    final payload = jsonDecode(queued.payload) as Map<String, dynamic>;
    expect(payload['commune_id'], 24091);
    final submission = (await db.select(db.mineSubmissions).get()).singleWhere(
      (entry) => entry.nom == 'Mine avec commune',
      orElse: () => throw StateError('soumission introuvable'),
    );
    expect(submission.communeId, 24091);
  });

  test('supprime la proposition, sa file et ses photos locales', () async {
    final created = await repository.create(
      name: 'Mine à supprimer',
      photos: [for (var i = 1; i <= 5; i++) _photo(i, storage)],
      agentLogin: 'eddy',
    );
    final submission = created.getOrElse((_) => throw StateError('création'));
    final storedPaths = submission.photos
        .map((part) => part.photo.path)
        .toList();

    final deleted = await repository.delete(submission.payloadId);

    expect(deleted.isRight(), isTrue);
    expect(await db.select(db.mineSubmissions).get(), isEmpty);
    expect(await db.select(db.mineSubmissionPhotos).get(), isEmpty);
    expect(await db.select(db.syncQueue).get(), isEmpty);
    expect(await db.select(db.mines).get(), isEmpty);
    for (var attempt = 0; attempt < 50; attempt++) {
      if (storedPaths.every((path) => !File(path).existsSync())) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(storedPaths.every((path) => !File(path).existsSync()), isTrue);
  });
}
