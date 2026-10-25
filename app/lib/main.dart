import 'package:app/config/init.dart';
import 'package:app/config/theme.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/pages/home_page.dart';
import 'package:app/pages/setup_page.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/theme_mode_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() async {
  final container = await preInit();
  await container.redux(accountProvider).dispatchAsync(RestoreLocalInstanceAction());
  final account = container.redux(accountProvider).dispatchTakeResult(RestoreAccountAction());

  runApp(
    RefenaScope.withContainer(
      container: container,
      child: TranslationProvider(
        child: MyApp(
          home: account == null ? const SetupPage() : const HomePage(),
        ),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final Widget home;

  const MyApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Repolupe',

      theme: getTheme(Brightness.light),
      darkTheme: getTheme(Brightness.dark),
      themeMode: context.watch(themeModeProvider),

      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      navigatorKey: context.read(navigationProvider).key,
      scaffoldMessengerKey: context.read(snackBarProvider).key,

      // Flutter keeps the keyboard open on mobile like native apps do, which leaves no way to close it
      // for multiline and number fields on iOS. Scrolling or tapping outside a text field closes it,
      // except on widgets wrapped in a TextFieldTapRegion.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      ),
      builder: (context, child) => Actions(
        actions: {
          EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) => intent.focusNode.unfocus(),
          ),
        },
        child: child!,
      ),

      home: home,
    );
  }
}
