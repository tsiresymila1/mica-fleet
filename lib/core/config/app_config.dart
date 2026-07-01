import 'package:flutter/foundation.dart';

/// Configuration d'exécution via `--dart-define` (indépendante du mode debug).
///
/// Exemples :
///   flutter run --dart-define=MICA_DEMO=true
///   flutter build apk --release \
///     --dart-define=MICA_DEMO=false \
///     --dart-define=MICA_ODOO_URL=https://odoo.mondomaine.mg/api
class AppConfig {
  /// Mode démo : faux backend de sync + seed local + menu Scénarios.
  /// Par défaut = mode debug (comportement actuel), surchargé par le flag.
  static const bool demo =
      bool.fromEnvironment('MICA_DEMO', defaultValue: kDebugMode);

  /// URL de base de l'API Odoo (utilisée hors mode démo).
  static const String odooBaseUrl = String.fromEnvironment(
    'MICA_ODOO_URL',
    defaultValue: 'https://odoo.example/api',
  );
}
