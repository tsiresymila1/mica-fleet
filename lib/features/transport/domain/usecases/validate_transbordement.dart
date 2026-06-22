import '../../../../core/utils/geo.dart';
import '../entities/transbordement.dart';

class ValidateTransbordement {
  /// Marque chaque maillon conforme si distance décharge↔recharge ≤ rayon.
  List<Transbordement> call(List<Transbordement> chaine, double rayonMetres) {
    return chaine.map((m) {
      if (m.gpsDechargeLat == null || m.gpsRechargeLat == null) {
        return m.copyWith(conforme: false);
      }
      final ok = isWithinRadius(m.gpsDechargeLat!, m.gpsDechargeLon!,
          m.gpsRechargeLat!, m.gpsRechargeLon!, rayonMetres);
      return m.copyWith(conforme: ok);
    }).toList();
  }

  /// Cohérence de chaîne : plaqueApres[i] == plaqueAvant[i+1].
  bool chaineCoherente(List<Transbordement> chaine) {
    for (var i = 0; i < chaine.length - 1; i++) {
      if (chaine[i].plaqueApres != chaine[i + 1].plaqueAvant) return false;
    }
    return true;
  }
}
