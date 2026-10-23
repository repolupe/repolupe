import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

final themeModeProvider = ReduxProvider<ThemeModeService, ThemeMode>((ref) {
  return ThemeModeService(persistence: ref.read(persistenceProvider));
});

/// Whether the app is light, dark or follows the system, stored on the device only.
class ThemeModeService extends ReduxNotifier<ThemeMode> {
  final PersistenceService _persistence;

  ThemeModeService({required this._persistence});

  @override
  ThemeMode init() => _persistence.getThemeMode();
}

/// Switches to [mode] and stores it.
class SetThemeModeAction extends AsyncReduxAction<ThemeModeService, ThemeMode> {
  final ThemeMode mode;

  SetThemeModeAction(this.mode);

  @override
  Future<ThemeMode> reduce() async {
    await notifier._persistence.setThemeMode(mode);
    return mode;
  }
}
