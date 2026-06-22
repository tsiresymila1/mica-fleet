import '../entities/transbordement.dart';

class RemoveTransbordement {
  /// Retire le maillon d'ordre donné et renumérote la chaîne.
  List<Transbordement> call(List<Transbordement> chaine, int ordre) {
    final filtree = chaine.where((m) => m.ordre != ordre).toList();
    for (var i = 0; i < filtree.length; i++) {
      filtree[i] = filtree[i].copyWith(ordre: i + 1);
    }
    return filtree;
  }
}
