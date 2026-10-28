import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/server_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/server.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/api.dart';
import 'support/fake_user.dart';
import 'support/rust.dart';

const _adminId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';

/// The subtitle of the tile with [key], `null` if it has none or no text.
String? _subtitle(WidgetTester tester, String key) {
  final subtitle = tester.widget<ListTile>(find.byKey(ValueKey(key))).subtitle;
  return subtitle is Text ? subtitle.data : null;
}

/// Opens the page for an admin of a server with version `1.2.3`. With [local], the active account is the local
/// instance's, while the requests are answered all the same. Returns the texts copied to the clipboard.
Future<List<String>> _pumpPage(WidgetTester tester, {required bool local}) async {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

  final account = fakeAccount(userId: _adminId, userName: 'admin');
  final container = (await tester.runAsync(
    () => mockContainer(
      account: account,
      stored: local ? account.copyWith(apiUrl: null) : account,
      api: (mock) {
        mock.on<ApiGetMeAction>((state, _) => (state, fakeUser(id: _adminId, userName: 'admin', role: UserRole.admin)));
        mock.on<ApiGetServerAction>((state, _) => (state, const ServerDto(version: '1.2.3')));
      },
    ),
  ))!;
  await container.redux(meProvider).dispatchAsync(RefreshMeAction());

  await tester.pumpWidget(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MaterialApp(
          navigatorKey: container.read(navigationProvider).key,
          scaffoldMessengerKey: container.read(snackBarProvider).key,
          home: const ServerPage(),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.text('1.2.3'), findsOneWidget);
  return copied;
}

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  testWidgets('the server page shows the base URL and the version, tapping copies them', (tester) async {
    final copied = await _pumpPage(tester, local: false);
    expect(_subtitle(tester, 'server.baseUrl'), 'https://repolupe.test');
    expect(_subtitle(tester, 'server.version'), '1.2.3');

    await tester.tap(find.byKey(const ValueKey('server.baseUrl')));
    await tester.pump();
    expect(find.text('Copied to the clipboard.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('server.version')));
    await tester.pump();
    expect(copied, ['https://repolupe.test', '1.2.3']);
  });

  testWidgets('the local instance has no base URL to copy', (tester) async {
    final copied = await _pumpPage(tester, local: true);
    expect(_subtitle(tester, 'server.baseUrl'), 'This device');

    await tester.tap(find.byKey(const ValueKey('server.baseUrl')));
    await tester.pump();
    expect(copied, isEmpty);
  });
}
