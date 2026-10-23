import 'dart:async';
import 'dart:io';

import 'package:app/config/theme.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../support/persistence.dart';
import '../../support/rust.dart';
import 'fake_server.dart';
import 'frame.dart';
import 'sample_data.dart';

/// The system's monospace font for the code, which is neither in the app nor in golden_screenshot. Without it
/// (not on macOS), the code is rendered in Inter.
const _monospaceFontFile = '/System/Library/Fonts/SFNSMono.ttf';

/// Whether [_monospaceFontFile] was loaded as `monospace`.
var _hasMonospaceFont = false;

/// iPhone 17 Pro, labelled on App Store Connect as "iPhone with Dynamic Island (medium display)" (6.1″/6.3″), the
/// only required iPhone size. golden_screenshot's `GoldenScreenshotDevices.iphone` is the optional 6.9″ size.
const _iphone = ScreenshotDevice(
  platform: TargetPlatform.iOS,
  resolution: Size(1206, 2622),
  pixelRatio: 3,
  goldenSubFolder: 'iphoneScreenshots/',
  frameBuilder: ScreenshotFrame.iphone,
);

/// Call this at the top of every screenshot test's `main` before [screenshotGroup].
void initScreenshotTest() {
  setUpAll(() async {
    await initRustLib();
    final file = File(_monospaceFontFile);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      await (FontLoader('monospace')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      _hasMonospaceFont = true;
    }
  });

  ScreenshotDevice.screenshotsFolder = 'goldens/';
}

/// Runs one golden screenshot test per store device (iPhone, iPad, Android phone, Android tablet) rendering [home] for
/// the user [sampleUserId] of a server that answers with [routes] (see [ScreenshotServer]), framed with the
/// marketing [title]. [pushed] is opened above [home], so that it has a back button. [prepare] runs once the page
/// is shown, e.g. to open a chat; the screenshot is taken when
/// [ready] finds something and nothing is loading any more.
///
/// Goldens are written to `goldens/<deviceFolder>/<goldenFileName>.png`. They are not checked in, so without them
/// (e.g. in a fresh checkout) the tests are skipped unless they are written with `--update-goldens`.
void screenshotGroup({
  required String description,
  required String title,
  required Map<String, Object?> routes,
  required Widget home,
  Widget? pushed,
  required Finder ready,
  required String goldenFileName,
  Brightness brightness = Brightness.light,
  Future<void> Function(RefenaContainer container)? prepare,
}) {
  group(description, () {
    for (final (name, device) in [
      ('iphone', _iphone),
      ('ipad', GoldenScreenshotDevices.ipad.device),
      ('androidPhone', GoldenScreenshotDevices.androidPhone.device),
      ('androidTablet', GoldenScreenshotDevices.androidTablet.device),
    ]) {
      testGoldens('for $name', skip: !_hasGolden(device, goldenFileName), (tester) async {
        final server = await ScreenshotServer.start(tester, routes);
        final container = await _loggedIn(tester, server.apiUrl);

        await tester.pumpWidget(
          RefenaScope.withContainer(
            container: container,
            child: TranslationProvider(
              child: ScreenshotApp(
                device: device.wrapWithTitle(title: title),
                frameColors: brightness == Brightness.dark ? ScreenshotFrameColors.light : ScreenshotFrameColors.dark,
                theme: getTheme(brightness),
                navigatorKey: container.read(navigationProvider).key,
                scaffoldMessengerKey: container.read(snackBarProvider).key,
                home: home,
              ),
            ),
          ),
        );
        if (pushed != null) {
          unawaited(container.global.dispatchAsync(NavigateAction.push(pushed)));
          await tester.pump();
        }
        if (prepare != null) {
          await tester.runAsync(() => prepare(container));
        }
        await _pumpUntilLoaded(tester, ready);

        await tester.loadAssets(fontsToMock: [...kFontsToMock, if (!_hasMonospaceFont) 'monospace']);
        await tester.pumpAndSettle();
        await tester.expectScreenshot(device, goldenFileName);
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  });
}

/// Whether the golden of [device] named [goldenFileName] exists or is being written.
bool _hasGolden(ScreenshotDevice device, String goldenFileName) {
  final comparator = goldenFileComparator;
  if (autoUpdateGoldenFiles || comparator is! LocalFileComparator) {
    return true;
  }
  final path = '${ScreenshotDevice.screenshotsFolder}${device.goldenSubFolder}$goldenFileName.png';
  return File.fromUri(comparator.basedir.resolve(path)).existsSync();
}

/// A container whose active account is the sample user on the server at [apiUrl], with the user loaded.
Future<RefenaContainer> _loggedIn(WidgetTester tester, String apiUrl) async {
  final account = Account(
    apiUrl: apiUrl,
    token: 'session-token',
    user: AccountUser(id: sampleUserId, userName: sampleUserName),
  );
  final persistence = (await tester.runAsync(() => mockPersistence(account: account)))!;
  final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
  container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
  await tester.runAsync(() => container.redux(meProvider).dispatchAsync(RefreshMeAction()));
  return container;
}

/// Pumps until [ready] finds something and no progress indicator is left, letting the requests to the server run
/// meanwhile. Also those offstage, e.g. of a card a list built below the screen, whose request would never finish
/// in the pumps of the fake clock.
Future<void> _pumpUntilLoaded(WidgetTester tester, Finder ready) async {
  final progress = find.byType(CircularProgressIndicator, skipOffstage: false);
  for (var i = 0; i < 100 && (ready.evaluate().isEmpty || progress.evaluate().isNotEmpty); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready, findsWidgets);
  expect(progress, findsNothing);
}
