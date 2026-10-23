import 'package:app/config/locale.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/frb_generated.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:refena_inspector_client/refena_inspector_client.dart';

Future<RefenaContainer> preInit() async {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  initLogging(Level.INFO);

  await RustLib.init();

  final persistenceService = await PersistenceService.initialize();

  final ref = RefenaContainer(
    overrides: [
      persistenceProvider.overrideWithValue(persistenceService),
    ],
    observers: kDebugMode
        ? [
            RefenaDebugObserver(),
            RefenaInspectorObserver(),
            RefenaTracingObserver(),
          ]
        : [],
  );

  await initLocale(ref);

  return ref;
}

void initLogging(Level level) {
  Logger.root.level = level;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.time} ${'[${record.level.name}]'.padLeft(9)} [${record.loggerName}] ${record.message}');

    if (record.error != null) {
      // ignore: avoid_print
      print(record.error);
    }

    if (record.stackTrace != null) {
      // ignore: avoid_print
      print(record.stackTrace);
    }
  });
}
