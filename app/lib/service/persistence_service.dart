import 'dart:convert';

import 'package:app/model/account.dart';
import 'package:app/model/local_instance_secrets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _currentVersion = 1;

final persistenceProvider = Provider<PersistenceService>((ref) {
  throw Exception('persistenceProvider not initialized');
}, debugLabel: 'PersistenceService');

/// The persistence version
const _version = 'version';

/// The accounts the user is logged in with, as a JSON list. In the secure storage, since they contain the tokens.
const _accounts = 'accounts';

/// The [Account.key] of the account in use.
const _activeAccount = 'active_account';

/// The [LocalInstanceSecrets] as JSON, set on the local instance's first start. In the secure storage.
const _localInstance = 'local_instance';

/// The [ThemeMode.name] chosen by the user, [ThemeMode.system] if unset.
const _themeMode = 'theme_mode';

/// This service abstracts the persistence layer.
/// Secrets go into the secure storage (Keychain, Android Keystore), everything else into the shared preferences.
class PersistenceService {
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  /// The values in the secure storage, read on start, so that they can be read synchronously.
  final Map<String, String> _secrets;

  PersistenceService._(this._prefs, this._secureStorage, this._secrets);

  static Future<PersistenceService> initialize() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();

    if (prefs.getInt(_version) == null) {
      // The Keychain keeps its items when the app is uninstalled, which a new install must not use.
      await secureStorage.deleteAll();
      await prefs.setInt(_version, _currentVersion);
    }

    return PersistenceService._(prefs, secureStorage, {...await secureStorage.readAll()});
  }

  Future<void> _setSecret(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
    _secrets[key] = value;
  }

  List<Account> getAccounts() {
    final json = _secrets[_accounts];
    if (json == null) {
      return [];
    }
    return (jsonDecode(json) as List).map((e) => AccountMapper.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> setAccounts(List<Account> accounts) async {
    await _setSecret(_accounts, jsonEncode(accounts.map((a) => a.toMap()).toList()));
  }

  String? getActiveAccountKey() {
    return _prefs.getString(_activeAccount);
  }

  Future<void> setActiveAccountKey(String? key) async {
    if (key == null) {
      await _prefs.remove(_activeAccount);
    } else {
      await _prefs.setString(_activeAccount, key);
    }
  }

  LocalInstanceSecrets? getLocalInstanceSecrets() {
    final json = _secrets[_localInstance];
    return json == null ? null : LocalInstanceSecretsMapper.fromJson(json);
  }

  Future<void> setLocalInstanceSecrets(LocalInstanceSecrets secrets) async {
    await _setSecret(_localInstance, secrets.toJson());
  }

  ThemeMode getThemeMode() {
    final value = _prefs.getString(_themeMode);
    return ThemeMode.values.where((mode) => mode.name == value).firstOrNull ?? ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeMode, mode.name);
  }
}
