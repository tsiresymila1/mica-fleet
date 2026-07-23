import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';

/// Affiche une carte OpenStreetMap plein écran (modal) centrée sur [lat]/[lon]
/// avec un marqueur. Utilisé pour localiser une mine ou un dépôt.
Future<void> showLocationMap(
  BuildContext context, {
  required String titre,
  required double lat,
  required double lon,
  double? rayonMetres,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MapDialog(
        titre: titre, lat: lat, lon: lon, rayonMetres: rayonMetres),
  );
}

class _MapDialog extends StatelessWidget {
  final String titre;
  final double lat;
  final double lon;
  final double? rayonMetres;
  const _MapDialog({
    required this.titre,
    required this.lat,
    required this.lon,
    this.rayonMetres,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    // 0,0 = coordonnée non renseignée côté serveur : rien à pointer.
    final sansCoord = lat == 0 && lon == 0;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Container(
              color: AppColors.primary,
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(children: [
                const Icon(Icons.place, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(titre,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium!
                          .copyWith(color: Colors.white)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
            Expanded(
              child: sansCoord
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Position non renseignée pour ce lieu.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : FlutterMap(
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 14,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'net.radoran.mica',
                        ),
                        if (rayonMetres != null && rayonMetres! > 0)
                          CircleLayer(circles: [
                            CircleMarker(
                              point: point,
                              radius: rayonMetres!,
                              useRadiusInMeter: true,
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderColor: AppColors.primary,
                              borderStrokeWidth: 2,
                            ),
                          ]),
                        MarkerLayer(markers: [
                          Marker(
                            point: point,
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: const Icon(Icons.location_on,
                                color: AppColors.danger, size: 44),
                          ),
                        ]),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
