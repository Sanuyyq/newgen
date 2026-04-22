import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Хранилище секретов: VLESS uuid, AWG PrivateKey, PresharedKey.
///
/// В `profiles.config_json` кладётся ссылка вида `secret://<alias>`,
/// а реальное значение живёт здесь — в KeyStore/Keychain/DPAPI.
///
/// API осознанно узкий, чтобы нельзя было по ошибке дампить секреты наружу.
class SecretVault {
  SecretVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _prefix = 'negern.secret.';

  Future<void> write(String alias, String value) =>
      _storage.write(key: _prefix + alias, value: value);

  Future<String?> read(String alias) =>
      _storage.read(key: _prefix + alias);

  Future<void> delete(String alias) =>
      _storage.delete(key: _prefix + alias);

  Future<void> clear() async {
    final all = await _storage.readAll();
    for (final k in all.keys.where((k) => k.startsWith(_prefix))) {
      await _storage.delete(key: k);
    }
  }

  /// Если `value` имеет форму `secret://<alias>`, возвращает реальный секрет
  /// из vault. Иначе — сам `value` без изменений (для обратной совместимости).
  Future<String> resolve(String value) async {
    const scheme = 'secret://';
    if (!value.startsWith(scheme)) return value;
    final alias = value.substring(scheme.length);
    final v = await read(alias);
    if (v == null) {
      throw StateError('Secret alias "$alias" not found in vault');
    }
    return v;
  }
}

final secretVaultProvider = Provider<SecretVault>((_) => SecretVault());
