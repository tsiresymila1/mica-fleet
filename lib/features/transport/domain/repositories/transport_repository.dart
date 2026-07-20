import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/transbordement.dart';

abstract class TransportRepository {
  /// Remplace la chaîne de transbordements d'UN lot (unité indivisible).
  Future<Either<Failure, Unit>> persistChaine(
      String lotId, List<Transbordement> chaine);

  Future<List<Transbordement>> chaineFor(String lotId);
}
