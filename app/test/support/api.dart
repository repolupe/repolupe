import 'package:app/model/account.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'persistence.dart';

/// An account on a server that is never contacted, since the tests answer the API actions
/// (`apiProvider.overrideWithActions`).
Account fakeAccount({required String userId, String userName = 'alice'}) => Account(
  apiUrl: 'https://repolupe.test',
  token: 'session-token',
  user: AccountUser(id: userId, userName: userName),
);

/// The answers to the actions of [apiProvider], see `overrideWithActions`.
typedef ApiMocks = ReduxActionOverrides<ApiService, AccountClient?>;

/// A container on empty in-memory storage, logged in to [account], whose API actions are answered by [api] and that
/// has the other [overrides]. The account is stored as [stored] (defaults to [account]), e.g. as a local account whose
/// requests are answered all the same. In widget tests, call it in `tester.runAsync`.
Future<RefenaContainer> mockContainer({
  required Account account,
  Account? stored,
  void Function(ApiMocks mock)? api,
  List<ProviderOverride> overrides = const [],
}) async {
  final persistence = await mockPersistence(account: stored ?? account);
  final container = RefenaContainer(
    overrides: [
      persistenceProvider.overrideWithValue(persistence),
      if (api != null) apiProvider.overrideWithActions(api),
      ...overrides,
    ],
  );
  container.redux(apiProvider).dispatch(ApiSetAccountAction(account));
  return container;
}

/// The error of an API action that the server answered with [code].
ClientError apiError(ErrorCode code, {int status = 400, String message = 'Error'}) => ClientError.api(status: status, code: code, message: message);
