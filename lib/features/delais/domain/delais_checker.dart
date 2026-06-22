enum DelaiStatut { ok, bientotEchu, depasse }

class DelaisChecker {
  /// Compare le temps écoulé à la limite. [seuilAvant] = fraction déclenchant l'alerte préventive.
  DelaiStatut statut(Duration ecoule, Duration limite,
      {double seuilAvant = 0.8}) {
    if (ecoule > limite) return DelaiStatut.depasse;
    if (ecoule >= limite * seuilAvant) return DelaiStatut.bientotEchu;
    return DelaiStatut.ok;
  }

  /// Ratio pour le scoring (catégorie B).
  double ratio(Duration ecoule, Duration limite) =>
      ecoule.inSeconds / limite.inSeconds;
}
