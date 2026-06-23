class Mine {
  final String id;
  final String nom;
  final double lat;
  final double lon;
  final double rayonMetres;
  final String? district;
  final String? commune;
  final String? region;
  final bool actif;

  const Mine({
    required this.id,
    required this.nom,
    required this.lat,
    required this.lon,
    this.rayonMetres = 20,
    this.district,
    this.commune,
    this.region,
    this.actif = true,
  });
}
