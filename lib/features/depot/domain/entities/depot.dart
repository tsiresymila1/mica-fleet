import 'package:freezed_annotation/freezed_annotation.dart';
part 'depot.freezed.dart';

@freezed
abstract class Depot with _$Depot {
  const factory Depot({
    required String id,
    required String nom,
    required double lat,
    required double lon,
    @Default(20) double rayonMetres,
    @Default(true) bool actif,
  }) = _Depot;
}
