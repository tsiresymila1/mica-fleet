import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Stocke le Bearer token Odoo de façon chiffrée (Android Keystore).
/// Repli sur le flag --dart-define MICA_ODOO_TOKEN si rien n'est stocké.
class SecureTokenStore {
  static const _key = 'odoo_bearer_token';
  final _storage = const FlutterSecureStorage();

  Future<String?> read() async {
    final stored = await _storage.read(key: _key);
    if (stored != null && stored.isNotEmpty) return stored;
    return AppConfig.odooToken.isEmpty ? null : AppConfig.odooToken;
  }

  Future<void> save(String token) => _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}
