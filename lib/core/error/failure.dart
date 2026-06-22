import 'package:freezed_annotation/freezed_annotation.dart';
part 'failure.freezed.dart';

@freezed
sealed class Failure with _$Failure {
  const factory Failure.network([String? message]) = NetworkFailure;
  const factory Failure.database([String? message]) = DatabaseFailure;
  const factory Failure.auth([String? message]) = AuthFailure;
  const factory Failure.validation(String message) = ValidationFailure;
  const factory Failure.mockLocation() = MockLocationFailure;
  const factory Failure.unexpected([String? message]) = UnexpectedFailure;
}
