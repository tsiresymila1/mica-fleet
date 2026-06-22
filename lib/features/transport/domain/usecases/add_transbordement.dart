import '../entities/transbordement.dart';

class AddTransbordement {
  /// Ajoute un maillon en fin de chaîne, ordre = taille+1.
  List<Transbordement> call(
      List<Transbordement> chaine, Transbordement maillon) {
    final ordre = chaine.length + 1;
    return [...chaine, maillon.copyWith(ordre: ordre)];
  }
}
