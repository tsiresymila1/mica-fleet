import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';

class ValidateChargement {
  /// Niveau 1 (extrait Phase 1) : ≥1 mine, ≤3, photo + GPS présents par mine.
  Either<Failure, Chargement> call(Chargement c) {
    if (c.mines.isEmpty) {
      return left(const Failure.validation('Au moins une mine requise'));
    }
    if (c.mines.length > 3) {
      return left(const Failure.validation('Maximum 3 mines'));
    }
    for (final m in c.mines) {
      if (m.photo == null) {
        return left(
            Failure.validation('Photo manquante pour la mine ${m.mineId}'));
      }
    }
    return right(c.copyWith(statut: 'valide'));
  }
}
