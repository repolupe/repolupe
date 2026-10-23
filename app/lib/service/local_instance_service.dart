import 'dart:io';

import 'package:app/model/local_instance_secrets.dart';
import 'package:app/src/rust/api/local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

final localInstanceProvider = ReduxProvider<LocalInstanceService, LocalHandle?>((ref) {
  return LocalInstanceService();
});

/// The Repolupe instance running in the app, which local accounts send their requests to (in-process, through
/// the Rust client). The state is its handle, `null` while it is not running. It runs while there is a local
/// account, see the account service.
class LocalInstanceService extends ReduxNotifier<LocalHandle?> {
  /// The directory with the instance's database, repositories and attachments.
  final Future<String> Function() _dataDir;

  LocalInstanceService({Future<String> Function()? dataDir}) : _dataDir = dataDir ?? _defaultDataDir;

  @override
  LocalHandle? init() => null;
}

/// `local` in the app's support directory, which is not shown to the user.
Future<String> _defaultDataDir() async {
  final support = await getApplicationSupportDirectory();
  return '${support.path}${Platform.pathSeparator}local';
}

/// Starts the instance with [secrets], unless it is running already, and returns it.
/// Throws [LocalError] if it fails, e.g. if the data directory can't be written.
class StartLocalInstanceAction extends AsyncReduxActionWithResult<LocalInstanceService, LocalHandle?, LocalHandle> {
  final LocalInstanceSecrets secrets;

  StartLocalInstanceAction(this.secrets);

  @override
  Future<(LocalHandle?, LocalHandle)> reduce() async {
    final running = state;
    if (running != null && running.isRunning()) {
      return (running, running);
    }
    final instance = await startLocal(
      config: LocalConfig(
        dataDir: await notifier._dataDir(),
        tokenEncryptionKey: secrets.tokenEncryptionKey,
        adminPassword: secrets.password,
      ),
    );
    return (instance, instance);
  }

  @override
  String toString() => 'StartLocalInstanceAction()';
}

/// Stops the instance, keeping its data, so that it can be started again. Its clients' requests fail from then on.
class StopLocalInstanceAction extends AsyncReduxAction<LocalInstanceService, LocalHandle?> {
  @override
  Future<LocalHandle?> reduce() async {
    await state?.shutdown();
    return null;
  }
}
