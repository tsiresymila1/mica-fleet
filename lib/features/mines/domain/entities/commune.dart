class Commune {
  final int id;
  final String nom;
  final String? district;
  final bool actif;

  const Commune({
    required this.id,
    required this.nom,
    required this.actif,
    this.district,
  });
}
