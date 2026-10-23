import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The default instance name.
const productName = 'Repolupe';

/// The name of the active account's server (`INSTANCE_NAME`), loaded again when the account changes.
/// [productName] without an account or if it fails to load.
final instanceNameProvider = FutureProvider<String>((ref) async {
  if (ref.watch(apiProvider) == null) {
    return productName;
  }
  try {
    final instance = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiGetInstanceAction());
    return instance.name;
  } on ClientError {
    return productName;
  }
});
