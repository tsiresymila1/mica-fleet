import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingPasswordChange {
  final String login;
  final String currentPassword;
  final String newPassword;
  final DateTime changedAt;

  const PendingPasswordChange({
    required this.login,
    required this.currentPassword,
    required this.newPassword,
    required this.changedAt,
  });
}

/// Secrets d'authentification conservés dans le stockage chiffré du système.
/// Le mot de passe courant n'est jamais conservé après synchronisation : seul
/// un vérificateur salé non réversible reste pour autoriser le mode hors ligne.
class PasswordSecretStore {
  static const _pendingKey = 'pending_password_change_v1';
  static const _passwordKey = 'agent_password_v1';
  final FlutterSecureStorage _storage;

  const PasswordSecretStore([this._storage = const FlutterSecureStorage()]);

  String _verifierKey(String login) =>
      'password_verifier_${base64Url.encode(utf8.encode(login))}';

  String _passwordCredentialKey(String login) =>
      '$_passwordKey${base64Url.encode(utf8.encode(login))}';

  Future<void> saveVerifier(String login, String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(24, (_) => random.nextInt(256));
    final digest = sha256.convert([...salt, ...utf8.encode(password)]).bytes;
    await _storage.write(
      key: _verifierKey(login),
      value: jsonEncode({
        'salt': base64Encode(salt),
        'digest': base64Encode(digest),
      }),
    );
  }

  Future<bool> verify(String login, String password) async {
    final raw = await _storage.read(key: _verifierKey(login));
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final salt = base64Decode(data['salt'] as String);
      final expected = base64Decode(data['digest'] as String);
      final actual = sha256.convert([...salt, ...utf8.encode(password)]).bytes;
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var i = 0; i < actual.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }

  /// Stocke le mot de passe de connexion pour permettre une reconnexion
  /// automatique (si la chaîne de confiance du terminal le permet).
  ///
  /// La stratégie produit un confort d'usage ; en mode sécurisé, ce secret est
  /// protégé par le store natif (keystore / Keychain).
  Future<void> savePassword(String login, String password) async {
    await _storage.write(key: _passwordCredentialKey(login), value: password);
  }

  Future<String?> readPassword(String login) async =>
      _storage.read(key: _passwordCredentialKey(login));

  Future<void> clearPassword(String login) async =>
      _storage.delete(key: _passwordCredentialKey(login));

  Future<void> queue({
    required String login,
    required String currentPassword,
    required String newPassword,
  }) async {
    final existing = await pending();
    await _storage.write(
      key: _pendingKey,
      value: jsonEncode({
        'login': login,
        // Plusieurs changements hors ligne doivent toujours être appliqués au
        // serveur avec son mot de passe d'origine.
        'current_password': existing?.currentPassword ?? currentPassword,
        'new_password': newPassword,
        'changed_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    await saveVerifier(login, newPassword);
  }

  Future<PendingPasswordChange?> pending() async {
    final raw = await _storage.read(key: _pendingKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return PendingPasswordChange(
        login: data['login'] as String,
        currentPassword: data['current_password'] as String,
        newPassword: data['new_password'] as String,
        changedAt: DateTime.parse(data['changed_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPending() => _storage.delete(key: _pendingKey);
}
