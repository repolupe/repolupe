import 'package:app/config/locale.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/persistence.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  UserDto user({String? locale}) => UserDto(
    id: UuidValue.fromString('0195f2a0-0000-7000-8000-000000000001'),
    role: UserRole.user,
    userName: 'alice',
    canLogin: true,
    canManageRepositories: true,
    canChangeIdentity: true,
    mustChangePassword: false,
    locale: locale,
    autoCommit: false,
    createdAt: DateTime.utc(2026, 10, 20),
  );

  test("the locale and the formats follow the user's language, else the device's", () async {
    binding.platformDispatcher.localesTestValue = const [Locale('fr', 'FR'), Locale('de', 'CH')];
    addTearDown(binding.platformDispatcher.clearLocalesTestValue);
    final persistence = await mockPersistence();
    final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);

    Future<void> setLocale(String? locale) async {
      container.redux(meProvider).dispatch(SetMeAction(user(locale: locale)));
      // the stream delivers the change, then the deferred translations load
      await pumpEventQueue();
    }

    await initLocale(container);
    expect(LocaleSettings.currentLocale, AppLocale.de);
    expect(Intl.defaultLocale, 'de_CH');

    await setLocale('en-GB');
    expect(LocaleSettings.currentLocale, AppLocale.en);
    expect(Intl.defaultLocale, 'en_GB');

    // not translated, so formatted like the texts
    await setLocale('fr-FR');
    expect(LocaleSettings.currentLocale, AppLocale.en);
    expect(Intl.defaultLocale, 'en');

    // no formats for it, so formatted like its language
    await setLocale('de-LI');
    expect(LocaleSettings.currentLocale, AppLocale.de);
    expect(Intl.defaultLocale, 'de');

    await setLocale(null);
    expect(LocaleSettings.currentLocale, AppLocale.de);
    expect(Intl.defaultLocale, 'de_CH');
  });
}
