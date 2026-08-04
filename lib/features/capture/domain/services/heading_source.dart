class HeadingFix {
  final double degrees;
  final double? accuracy;
  final String reference;

  const HeadingFix({
    required this.degrees,
    required this.reference,
    this.accuracy,
  });
}

/// Direction visée par la caméra au moment de la prise de vue.
abstract class HeadingSource {
  Future<HeadingFix?> current();
}
