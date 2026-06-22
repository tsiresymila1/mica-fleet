import 'package:freezed_annotation/freezed_annotation.dart';
part 'score_result.freezed.dart';

@freezed
abstract class ScoreResult with _$ScoreResult {
  const factory ScoreResult({
    required bool eligible,
    required int score, // 0..100 (0 si non éligible)
    required String statut, // 'rejete' | 'evalue'
  }) = _ScoreResult;
}
