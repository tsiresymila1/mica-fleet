import 'package:geolocator/geolocator.dart';

/// Garantit que la localisation est utilisable : service activé + permission
/// accordée (demande au runtime si nécessaire). Lève une exception explicite
/// sinon — Android 6+ exige la demande de permission à l'exécution.
Future<void> ensureLocationReady() async {
  final serviceOn = await Geolocator.isLocationServiceEnabled();
  if (!serviceOn) {
    throw Exception('Active le GPS du téléphone');
  }

  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied) {
    throw Exception('Permission GPS refusée');
  }
  if (perm == LocationPermission.deniedForever) {
    throw Exception('Permission GPS bloquée — autorise-la dans les réglages');
  }
}
