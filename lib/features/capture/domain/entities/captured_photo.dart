import 'package:freezed_annotation/freezed_annotation.dart';
part 'captured_photo.freezed.dart';

@freezed
abstract class CapturedPhoto with _$CapturedPhoto {
  const factory CapturedPhoto({
    required String path,
    required String sha256,
    required double lat,
    required double lon,
    required double precision,
    required DateTime takenAt,
  }) = _CapturedPhoto;
}
