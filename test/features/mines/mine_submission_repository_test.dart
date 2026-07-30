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
    expect(Uuid.isValidUUID(fromString: submission.payloadId), isTrue);
    expect(Uuid.isValidUUID(fromString: submission.deviceUuid), isTrue);
    expect(submission.state, 'local_pending');
    expect(await db.select(db.mines).get(), isEmpty);

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
    expect(payload['positions'], hasLength(5));
    final firstHash = (payload['positions'] as List).first['hash'] as String;
    expect(firstHash, hasLength(64));
    expect(firstHash, photos.first.hash);
    expect(photos.every((photo) => File(photo.path).existsSync()), isTrue);
  });
}
