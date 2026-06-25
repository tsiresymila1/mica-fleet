enum DelaiAlerte { avantEcheance, echeance }

typedef RappelDelai = ({DateTime quand, DelaiAlerte type, String message});

/// Calcule les rappels à programmer pour un chargement, à partir de sa date de
/// début et du délai limite. Pur et testable — la livraison (notification)
/// est faite ailleurs.
class DelaiAlertPlanner {
  /// [seuil] = fraction du délai déclenchant l'alerte préventive (ex. 0.8 = 80 %).
  List<RappelDelai> planifier(DateTime debut, Duration limite,
      {double seuil = 0.8}) {
    final avant = debut.add(
        Duration(seconds: (limite.inSeconds * seuil).round()));
    final echeance = debut.add(limite);
    return [
      (
        quand: avant,
        type: DelaiAlerte.avantEcheance,
        message: 'Bientôt en retard — livre le chargement au dépôt',
      ),
      (
        quand: echeance,
        type: DelaiAlerte.echeance,
        message: 'Délai atteint — livre le chargement maintenant',
      ),
    ];
  }
}
