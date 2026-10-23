import 'package:app/model/account.dart';
import 'package:app/model/local_instance_secrets.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final account = Account(
    apiUrl: 'https://repolupe.example.com',
    token: 'session-token',
    user: AccountUser(id: '0195f2a0-0000-7000-8000-000000000001', userName: 'alice'),
  );
  final secrets = LocalInstanceSecrets(tokenEncryptionKey: 'key', userName: 'admin', password: 'password');

  test('the secrets are stored in the secure storage', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final persistence = await PersistenceService.initialize();
    await persistence.setAccounts([account]);
    await persistence.setLocalInstanceSecrets(secrets);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'version'});
    final stored = await const FlutterSecureStorage().readAll();
    expect(stored.keys, unorderedEquals(['accounts', 'local_instance']));

    final again = await PersistenceService.initialize();
    expect(again.getAccounts().single.token, 'session-token');
    expect(again.getLocalInstanceSecrets()!.password, 'password');
  });

  test('a new install ignores the secrets of an earlier one', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'local_instance': secrets.toJson()});
    final persistence = await PersistenceService.initialize();

    expect(persistence.getLocalInstanceSecrets(), isNull);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
}
