import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../capture/domain/entities/captured_photo.dart';
part 'lot.freezed.dart';

/// LOT = chargement d'UNE mine. Indivisible : la quantité de départ prime.
/// C'est l'unité de traçabilité, de numéro de lot et de score.
@freezed
abstract class Lot with _$Lot {
  const factory Lot({
    required String id, // ex. MICA-2026-0007-L1
    required String mineId,
    String? reference,
    String? couleur,
    double? quantiteEstimee,
    String? plaqueDepart,
    CapturedPhoto? photo,
    @Default('en_cours') String statut,
    String? deviceUuid,
    int? score,
  }) = _Lot;
}
