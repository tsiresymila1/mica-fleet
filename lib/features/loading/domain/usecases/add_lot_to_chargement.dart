import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';
import '../entities/lot.dart';

/// Ajoute un lot (chargement d'UNE mine) à la session. Max 3 mines, une seule
/// fois par mine — le lot est indivisible.
class AddLotToChargement {
  Either<Failure, Chargement> call(Chargement c, Lot lot) {
    if (!c.peutAjouterLot) {
      return left(const Failure.validation('Maximum 3 mines par chargement'));
    }
    if (c.lots.any((x) => x.mineId == lot.mineId)) {
      return left(const Failure.validation('Mine déjà ajoutée'));
    }
    // Identifiant de lot déterministe : <session>-L<n>
    final withId = lot.copyWith(id: '${c.id}-L${c.lots.length + 1}');
    return right(c.copyWith(lots: [...c.lots, withId]));
  }
}
