abstract class PlateOcrService {
  /// Renvoie la plaque détectée ou null si illisible (→ saisie manuelle).
  Future<String?> readPlate(String imagePath);
}
