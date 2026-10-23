import 'dart:io';

import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/local_instance_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/persistence.dart';
import 'support/rust.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initRustLib();
  });

  test('a local account starts the instance, logs in again, and is restored on the next start', () async {
    final dataDir = await Directory.systemTemp.createTemp('repolupe-local-');
    addTearDown(() => dataDir.delete(recursive: true));
    final persistence = await mockPersistence();

    RefenaContainer app() => RefenaContainer(
      overrides: [
        persistenceProvider.overrideWithValue(persistence),
        localInstanceProvider.overrideWithNotifier((ref) => LocalInstanceService(dataDir: () async => dataDir.path)),
      ],
    );

    var container = app();
    await container.redux(accountProvider).dispatchAsync(CreateLocalAccountAction());
    final account = container.read(accountProvider).active!;
    expect(account.isLocal, isTrue);
    expect(account.server, 'This device');
    expect(account.key, 'local#${account.user.id}');
    expect(account.user.userName, 'admin');
    expect(File('${dataDir.path}/repolupe.db').existsSync(), isTrue);
    final me = await container.redux(apiProvider).dispatchAsyncTakeResult(ApiGetMeAction());
    expect(me.userName, 'admin');
    expect(me.mustChangePassword, isFalse);

    // The changed password is stored, so logging in again uses it.
    final secrets = persistence.getLocalInstanceSecrets()!;
    final error = await container
        .redux(meProvider)
        .dispatchAsyncTakeResult(
          ChangePasswordAction(currentPassword: secrets.password, newPassword: 'new-password', confirmPassword: 'new-password'),
        );
    expect(error, isNull);
    expect(persistence.getLocalInstanceSecrets()!.password, 'new-password');
    expect(persistence.getLocalInstanceSecrets()!.tokenEncryptionKey, secrets.tokenEncryptionKey);

    // Logging out removes the account and stops the instance, but keeps its data.
    await container.redux(accountProvider).dispatchAsync(LogoutAction());
    expect(container.read(accountProvider).accounts, isEmpty);
    expect(container.read(localInstanceProvider), isNull);

    await container.redux(accountProvider).dispatchAsync(CreateLocalAccountAction());
    final again = container.read(accountProvider).active!;
    expect(again.user.id, account.user.id);
    expect(again.token, isNot(account.token));

    // The next start of the app starts the instance again before restoring the account.
    await container.redux(localInstanceProvider).dispatchAsync(StopLocalInstanceAction());
    container = app();
    addTearDown(() => container.redux(localInstanceProvider).dispatchAsync(StopLocalInstanceAction()));
    await container.redux(accountProvider).dispatchAsync(RestoreLocalInstanceAction());
    final restored = container.redux(accountProvider).dispatchTakeResult(RestoreAccountAction());
    expect(restored?.key, again.key);
    final restoredMe = await container.redux(apiProvider).dispatchAsyncTakeResult(ApiGetMeAction());
    expect(restoredMe.id, me.id);
  });
}
