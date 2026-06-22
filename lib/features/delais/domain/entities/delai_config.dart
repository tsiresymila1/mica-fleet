import 'package:freezed_annotation/freezed_annotation.dart';
part 'delai_config.freezed.dart';

@freezed
abstract class DelaiConfig with _$DelaiConfig {
  const factory DelaiConfig({
    @Default(Duration(hours: 24)) Duration mineVersCollecte,
    @Default(Duration(hours: 48)) Duration collecteVersDepot,
    @Default(Duration(hours: 72)) Duration directVersDepot,
    @Default(0.8) double seuilAlerteAvant, // 80% du délai
  }) = _DelaiConfig;
}
