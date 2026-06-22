import 'package:freezed_annotation/freezed_annotation.dart';
part 'fournisseur.freezed.dart';

@freezed
abstract class Fournisseur with _$Fournisseur {
  const factory Fournisseur({
    required String id,
    required String nom,
    @Default(true) bool actif,
  }) = _Fournisseur;
}
