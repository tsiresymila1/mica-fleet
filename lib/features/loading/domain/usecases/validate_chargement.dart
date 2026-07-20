import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';

class ValidateChargement {
  /// Éligibilité : 1 à 3 lots, chacun avec sa photo (preuve d'origine).
  Either<Failure, Chargement> call(Chargement c) {
    if (c.lots.isEmpty) {
      return left(const Failure.validation('Au moins une mine requise'));
    }
    if (c.lots.length > 3) {
      return left(const Failure.validation('Maximum 3 mines'));
    }
    for (final l in c.lots) {
      if (l.photo == null) {
        return left(
            Failure.validation('Photo manquante pour la mine ${l.mineId}'));
      }
    }
    return right(c.copyWith(statut: 'valide'));
  }
}
