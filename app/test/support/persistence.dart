import 'package:app/model/account.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A persistence service on empty in-memory storage, with [account] stored as the active account.
/// In widget tests, call it in `tester.runAsync`.
Future<PersistenceService> mockPersistence({Account? account}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final persistence = await PersistenceService.initialize();
  if (account != null) {
    await persistence.setAccounts([account]);
    await persistence.setActiveAccountKey(account.key);
  }
  return persistence;
}
