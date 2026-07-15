import 'package:freezed_annotation/freezed_annotation.dart';
import 'mine_chargement.dart';
part 'chargement.freezed.dart';

@freezed
abstract class Chargement with _$Chargement {
  const Chargement._();
  const factory Chargement({
    required String id,
    required String fournisseurId,
    required DateTime dateCreation,
    @Default('brouillon') String statut,
    @Default(<MineChargement>[]) List<MineChargement> mines,
    String? lotReference, // regroupement Odoo (optionnel)
  }) = _Chargement;

  bool get peutAjouterMine => mines.length < 3;
}
