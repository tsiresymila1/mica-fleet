/// Construit l'identifiant unique d'un chargement : MICA-YYYY-XXXX.
/// [sequence] est paddé sur 4 chiffres minimum.
String buildLoadingId(int year, int sequence) {
  final seq = sequence.toString().padLeft(4, '0');
  return 'MICA-$year-$seq';
}
