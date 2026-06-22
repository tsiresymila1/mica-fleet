import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';
import '../entities/mine_chargement.dart';

class AddMineToChargement {
  Either<Failure, Chargement> call(Chargement c, MineChargement m) {
    if (!c.peutAjouterMine) {
      return left(const Failure.validation('Maximum 3 mines par chargement'));
    }
    if (c.mines.any((x) => x.mineId == m.mineId)) {
      return left(const Failure.validation('Mine déjà ajoutée'));
    }
    return right(c.copyWith(mines: [...c.mines, m]));
  }
}
