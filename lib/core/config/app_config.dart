import 'package:flutter/foundation.dart';

/// Configuration d'exécution via `--dart-define` (indépendante du mode debug).
///
/// Exemples :
///   flutter run --dart-define=MICA_DEMO=true
///   flutter build apk --release \
///     --dart-define=MICA_DEMO=false \
///     --dart-define=MICA_ODOO_URL=https://odoo.mondomaine.mg
class AppConfig {
  /// Mode démo : faux backend de sync + seed local + menu Scénarios.
  /// Par défaut = mode debug (comportement actuel), surchargé par le flag.
  static const bool demo =
      bool.fromEnvironment('MICA_DEMO', defaultValue: kDebugMode);

  /// Racine du serveur Odoo, **sans** `/api` : les chemins des endpoints le
  /// contiennent déjà (`/api/login`, `/api/tracking/submit`…).
  /// Ex. `http://192.168.1.20:8069` ou `https://odoo.mondomaine.mg`.
  static const String odooBaseUrl = String.fromEnvironment(
    'MICA_ODOO_URL',
    defaultValue: 'https://odoo.example',
  );

  /// Bearer token Odoo par défaut (repli si rien n'est stocké de façon chiffrée).
  /// À ne pas mettre en dur : passer via --dart-define ou stocker à l'exécution.
  static const String odooToken =
      String.fromEnvironment('MICA_ODOO_TOKEN', defaultValue: '');
}
