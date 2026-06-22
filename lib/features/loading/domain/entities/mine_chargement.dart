import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../capture/domain/entities/captured_photo.dart';
part 'mine_chargement.freezed.dart';

@freezed
abstract class MineChargement with _$MineChargement {
  const factory MineChargement({
    required String mineId,
    String? reference,
    String? couleur,
    double? quantiteEstimee,
    String? plaqueOcr,
    CapturedPhoto? photo,
  }) = _MineChargement;
}
