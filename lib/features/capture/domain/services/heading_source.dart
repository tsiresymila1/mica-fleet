class HeadingFix {
  final double degrees;
  final double? accuracy;
  final String reference;

  const HeadingFix({
    required this.degrees,
    required this.reference,
    this.accuracy,
  });

  /// Sur Android, une précision absente correspond généralement à un capteur
  /// non calibré ou indisponible. Ce cap ne doit pas être persisté.
  bool get isReliable => accuracy != null;
}

/// Direction visée par la caméra au moment de la prise de vue.
abstract class HeadingSource {
  /// Mesures en direct, y compris celles qui nécessitent une calibration.
  Stream<HeadingFix> watch();

  /// Cap fiable mesuré au moment de la demande.
  Future<HeadingFix?> current();
}
