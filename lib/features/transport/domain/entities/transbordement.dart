import 'package:freezed_annotation/freezed_annotation.dart';
part 'transbordement.freezed.dart';

@freezed
abstract class Transbordement with _$Transbordement {
  const Transbordement._();
  const factory Transbordement({
    required int ordre,
    String? plaqueAvant,
    String? plaqueApres,
    double? gpsDechargeLat,
    double? gpsDechargeLon,
    double? gpsRechargeLat,
    double? gpsRechargeLon,
    String? photoDechargePath,
    String? photoRechargePath,
    @Default(false) bool conforme,
  }) = _Transbordement;
}
