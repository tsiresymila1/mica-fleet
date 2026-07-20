import 'package:freezed_annotation/freezed_annotation.dart';
import 'lot.dart';
part 'chargement.freezed.dart';

/// Session de collecte : les lots partis ensemble (1 à 3 mines).
/// L'unité tracée reste le LOT.
@freezed
abstract class Chargement with _$Chargement {
  const Chargement._();
  const factory Chargement({
    required String id,
    required String fournisseurId,
    required DateTime dateCreation,
    @Default('brouillon') String statut,
    @Default(<Lot>[]) List<Lot> lots,
    String? lotReference, // regroupement Odoo (optionnel)
  }) = _Chargement;

  bool get peutAjouterLot => lots.length < 3;
}
