import 'dart:async';
import 'dart:io';

import 'package:app/config/theme.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../support/api.dart';
import '../../support/rust.dart';
import 'frame.dart';
import 'sample_data.dart';

/// The system's monospace font for the code, which is neither in the app nor in golden_screenshot. Without it
/// (not on macOS), the code is rendered in Inter.
const _monospaceFontFile = '/System/Library/Fonts/SFNSMono.ttf';

/// Whether [_monospaceFontFile] was loaded as `monospace`.
var _hasMonospaceFont = false;

/// The system's emoji font for e.g. the flags of the LLM providers, as the test engine has no font fallback.
/// Without it (not on macOS), emojis are rendered as boxes.
const _emojiFontFile = '/System/Library/Fonts/Apple Color Emoji.ttc';

/// The family [_emojiFontFile] is loaded as, the fallback of every text style in the screenshots.
const _emojiFontFamily = 'emoji';

/// iPhone 17 Pro, labelled on App Store Connect as "iPhone with Dynamic Island (medium display)" (6.1″/6.3″), the
/// only required iPhone size. golden_screenshot's `GoldenScreenshotDevices.iphone` is the optional 6.9″ size.
const _iphone = ScreenshotDevice(
  platform: TargetPlatform.iOS,
  resolution: Size(1206, 2622),
  pixelRatio: 3,
  goldenSubFolder: 'iphoneScreenshots/',
  frameBuilder: ScreenshotFrame.iphone,
);

/// Call this at the top of every screenshot test's `main` before [screenshotGroup], with the [locale] of the folder
/// the test is in. The texts, dates and numbers are in that language.
void initScreenshotTest({AppLocale locale = AppLocale.en}) {
  setUpAll(() async {
    await initRustLib();
    await initializeDateFormatting();
    await LocaleSettings.setLocale(locale);
    Intl.defaultLocale = locale.languageTag;
    final file = File(_monospaceFontFile);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      await (FontLoader('monospace')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      _hasMonospaceFont = true;
    }
    final emojiFile = File(_emojiFontFile);
    if (emojiFile.existsSync()) {
      final bytes = await emojiFile.readAsBytes();
      await (FontLoader(_emojiFontFamily)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  ScreenshotDevice.screenshotsFolder = 'goldens/';
}

/// Runs one golden screenshot test per store device (iPhone, iPad, Android phone, Android tablet) rendering [home] for
/// the user [sampleUserId] with the API answering from [api], framed with the marketing [title]. [pushed] is opened
/// above [home], so that it has a back button. [prepare] runs once the page is shown, e.g. to open a chat; the
/// screenshot is taken when [ready] finds something and nothing is loading any more.
///
/// Goldens are written to `goldens/<deviceFolder>/<goldenFileName>.png`. They are not checked in, so without them
/// (e.g. in a fresh checkout) the tests are skipped unless they are written with `--update-goldens`.
void screenshotGroup({
  required String description,
  required String title,
  required SampleApi api,
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
        final container = await _loggedIn(tester, api);

        await tester.pumpWidget(
          RefenaScope.withContainer(
            container: container,
            child: TranslationProvider(
              child: ScreenshotApp(
                device: device.wrapWithTitle(title: title),
                frameColors: brightness == Brightness.dark ? ScreenshotFrameColors.light : ScreenshotFrameColors.dark,
                theme: _withEmojiFallback(getTheme(brightness)),
                locale: LocaleSettings.currentLocale.flutterLocale,
                supportedLocales: AppLocaleUtils.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
        await prepare?.call(container);
        await _pumpUntilLoaded(tester, ready);

        await tester.loadAssets(fontsToMock: [...kFontsToMock, if (!_hasMonospaceFont) 'monospace']);
        await tester.pumpAndSettle();
        await tester.expectScreenshot(device, goldenFileName);
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  });
}

/// [theme] with [_emojiFontFamily] as the fallback of its texts.
ThemeData _withEmojiFallback(ThemeData theme) {
  return theme.copyWith(textTheme: theme.textTheme.apply(fontFamilyFallback: const [_emojiFontFamily]));
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

/// A container whose active account is the sample user, with the API answering from [api] and the user loaded.
Future<RefenaContainer> _loggedIn(WidgetTester tester, SampleApi api) async {
  final container = (await tester.runAsync(
    () => mockContainer(
      account: fakeAccount(userId: sampleUserId, userName: sampleUserName),
      api: (mock) {
        mock.on<ApiGetMeAction>((state, _) => (state, api.me));
        mock.on<ApiGetInstanceAction>((state, _) => (state, api.instance));
        mock.on<ApiListModelsAction>((state, _) => (state, api.models));
        mock.on<ApiListRepositoriesAction>((state, _) => (state, api.repositories));
        mock.on<ApiGetRepositoryAction>((state, action) => (state, _found(_repository(api, action.id))));
        mock.on<ApiListRepositoryDocumentsAction>((state, action) => (state, _found(api.repositoryDocuments[action.id])));
        mock.on<ApiListRepositoryUsersAction>((state, action) => (state, _found(api.repositoryUsers[action.id])));
        mock.on<ApiListChatsAction>((state, _) => (state, ChatPageDto(items: api.chats)));
        mock.on<ApiGetChatAction>((state, action) => (state, _found(api.chatDetails[action.chatId])));
      },
    ),
  ))!;
  await container.redux(meProvider).dispatchAsync(RefreshMeAction());
  return container;
}

/// The repository [id] of [api], `null` if it has none.
RepositoryDto? _repository(SampleApi api, UuidValue id) => api.repositories.where((repository) => repository.id == id).firstOrNull;

/// [value], or the `NOT_FOUND` error of the API if it is `null`.
T _found<T>(T? value) => value ?? (throw apiError(ErrorCode.notFound, status: 404, message: 'Not found'));

/// Pumps until [ready] finds something and no progress indicator is left, also those offstage, e.g. of a card a list
/// built below the screen. Meanwhile, the calls into the Rust library that the API mocks don't answer (e.g. the
/// suggested LLM providers) run in the real async zone, as they would never finish in the pumps of the fake clock.
Future<void> _pumpUntilLoaded(WidgetTester tester, Finder ready) async {
  final progress = find.byType(CircularProgressIndicator, skipOffstage: false);
  for (var i = 0; i < 100 && (ready.evaluate().isEmpty || progress.evaluate().isNotEmpty); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready, findsWidgets);
  expect(progress, findsNothing);
}
