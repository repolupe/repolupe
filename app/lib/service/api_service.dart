import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/local_instance_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/local.dart';
import 'package:app/src/rust/api/stream.dart';
import 'package:app/src/rust/third_party/repolupe/dto/auth.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/src/rust/third_party/repolupe/dto/instance.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart' hide MessageEvent;
import 'package:uuid/uuid.dart';

part 'requests/admin_requests.dart';
part 'requests/auth_requests.dart';
part 'requests/chat_requests.dart';
part 'requests/repository_requests.dart';
part 'requests/user_requests.dart';

final _logger = Logger('ApiService');

/// The Rust [Client] of an account, sending the account's token.
class AccountClient {
  final Account account;
  final Client client;

  AccountClient._(this.account, this.client);

  /// Creates the client of [account], whose requests go to [local] if it is a local account.
  /// Throws [ClientError] if the account's server address is not a valid URL, or if [local] is not running.
  factory AccountClient.of(Account account, LocalHandle? local) {
    return AccountClient._(account, _newClient(account.apiUrl, local, token: account.token));
  }

  /// Without the client, which has nothing to show.
  @override
  String toString() => 'AccountClient($account)';
}

/// A client for the server at [apiUrl], or for [local] if [apiUrl] is `null`.
/// Throws [ClientError] if [apiUrl] is not a valid URL, or if [local] is not running.
Client _newClient(String? apiUrl, LocalHandle? local, {String? token}) {
  if (apiUrl != null) {
    return Client.remote(baseUrl: apiUrl, token: token);
  }
  if (local == null || !local.isRunning()) {
    throw const ClientError.transport(message: 'The local instance is not running.');
  }
  return Client.local(instance: local, token: token);
}

final apiProvider = ReduxProvider<ApiService, AccountClient?>((ref) {
  return ApiService(local: ref.notifier(localInstanceProvider));
});

/// Sends the API requests through the Rust [Client] of the active account.
/// The state is that client, `null` while the user is not logged in.
class ApiService extends ReduxNotifier<AccountClient?> {
  final LocalInstanceService _local;

  ApiService({required this._local});

  @override
  AccountClient? init() => null;

  /// The client of [account]: the active one if it is [account], else a new one.
  AccountClient _clientFor(Account account) {
    final active = state;
    if (active != null && active.account == account) {
      return active;
    }
    return AccountClient.of(account, _local.state);
  }
}

/// The device's languages as `Accept-Language`, e.g. `de-CH, en-US;q=0.9`, which the server
/// uses for users without a locale (e.g. for chat titles).
String? _acceptLanguage() {
  final locales = WidgetsBinding.instance.platformDispatcher.locales.take(9).toList();
  if (locales.isEmpty) {
    return null;
  }
  return [
    for (final (i, locale) in locales.indexed) i == 0 ? locale.toLanguageTag() : '${locale.toLanguageTag()};q=${(10 - i) / 10}',
  ].join(', ');
}

extension ClientErrorMessage on ClientError {
  /// The API's error code, `null` if the server did not send one.
  ErrorCode? get code => switch (this) {
    ClientError_Api(:final code) => code,
    _ => null,
  };

  /// A message to show the user: the text of the API's error code (the API's English message only for codes of a
  /// newer server), a generic one otherwise (the details are logged).
  String get userMessage => switch (this) {
    ClientError_Api(:final code, :final message) => code.text ?? message,
    ClientError_InvalidResponse(:final status) => t.base.errors.invalidResponse(status: status),
    ClientError_Transport() => t.base.errors.unreachable,
  };
}

extension on ErrorCode {
  /// The text of the code in the language of the UI, `null` for [ErrorCode.unknown].
  String? get text {
    final errors = t.base.errors;
    return switch (this) {
      ErrorCode.internalError => errors.internalError,
      ErrorCode.validationError => errors.validationError,
      ErrorCode.unsupportedMediaType => errors.unsupportedMediaType,
      ErrorCode.unauthorized => errors.unauthorized,
      ErrorCode.forbidden => errors.forbidden,
      ErrorCode.notFound => errors.notFound,
      ErrorCode.conflict => errors.conflict,
      ErrorCode.rateLimited => errors.rateLimited,
      ErrorCode.userNameTaken => errors.userNameTaken,
      ErrorCode.emailTaken => errors.emailTaken,
      ErrorCode.nameTaken => errors.nameTaken,
      ErrorCode.repoNotFound => errors.repoNotFound,
      ErrorCode.branchNotFound => errors.branchNotFound,
      ErrorCode.authFailed => errors.authFailed,
      ErrorCode.tokenRequired => errors.tokenRequired,
      ErrorCode.remoteUnreachable => errors.remoteUnreachable,
      ErrorCode.unknownRepository => errors.unknownRepository,
      ErrorCode.unknownUser => errors.unknownUser,
      ErrorCode.generationInProgress => errors.generationInProgress,
      ErrorCode.notRetryable => errors.notRetryable,
      ErrorCode.wrongPassword => errors.wrongPassword,
      ErrorCode.samePassword => errors.samePassword,
      ErrorCode.passwordChangeRequired => errors.passwordChangeRequired,
      ErrorCode.unknownModel => errors.unknownModel,
      ErrorCode.noModelConfigured => errors.noModelConfigured,
      ErrorCode.unavailable => errors.unavailable,
      ErrorCode.fileUnavailable => errors.fileUnavailable,
      ErrorCode.unknownAttachment => errors.unknownAttachment,
      ErrorCode.unknown => null,
    };
  }
}

/// Sends the requests for [account] from now on, for nobody if it is `null`.
/// Throws [ClientError] if the account's server address is not a valid URL, or if it is a local account and the
/// local instance is not running.
class ApiSetAccountAction extends ReduxAction<ApiService, AccountClient?> {
  final Account? account;

  ApiSetAccountAction(this.account);

  @override
  AccountClient? reduce() {
    final account = this.account;
    return account == null ? null : notifier._clientFor(account);
  }

  @override
  String toString() => 'ApiSetAccountAction($account)';
}

/// Creates the client of the active account again if it is the local one, after the local instance was started
/// again, since a client sends its requests to the instance it was created for. Keeps the client if the instance is
/// not running, whose requests fail then.
class ApiReconnectLocalAction extends ReduxAction<ApiService, AccountClient?> {
  @override
  AccountClient? reduce() {
    final active = state;
    if (active == null || !active.account.isLocal) {
      return state;
    }
    try {
      return AccountClient.of(active.account, notifier._local.state);
    } on ClientError catch (e) {
      _logger.warning('Cannot reconnect to the local instance: $e');
      return state;
    }
  }
}

/// Calls the API with the client of an account and returns the result.
/// Throws [ClientError] if it fails. `UNAUTHORIZED` means the session ended, so the account is removed
/// (see [SessionExpiredAction]) unless [expireOnUnauthorized] is `false`. `PASSWORD_CHANGE_REQUIRED` means
/// the user must change their password first, which opens the page for it (see [PasswordChangeRequiredAction]).
class _ApiCallAction<R> extends AsyncReduxActionWithResult<ApiService, AccountClient?, R> with GlobalActions {
  /// The client to send the request with instead of an account's (login).
  final Client? client;

  /// The account to send the request for, defaults to the active one.
  final Account? account;

  final Future<R> Function(Client client) call;

  final bool expireOnUnauthorized;

  _ApiCallAction({
    this.client,
    this.account,
    required this.call,
    this.expireOnUnauthorized = true,
  });

  @override
  Future<(AccountClient?, R)> reduce() async {
    final client = this.client;
    if (client != null) {
      return (state, await _call(client));
    }

    final account = this.account;
    final accountClient = account == null ? state : notifier._clientFor(account);
    if (accountClient == null) {
      throw StateError('Not logged in.');
    }
    try {
      return (state, await _call(accountClient.client));
    } on ClientError_Api catch (e) {
      if (e.code == ErrorCode.unauthorized && expireOnUnauthorized) {
        await global.dispatchAsync(SessionExpiredAction(accountClient.account));
      } else if (e.code == ErrorCode.passwordChangeRequired) {
        await global.dispatchAsync(PasswordChangeRequiredAction(accountClient.account));
      }
      rethrow;
    }
  }

  /// Sends the request with the device's current languages.
  Future<R> _call(Client client) async {
    client.setAcceptLanguage(acceptLanguage: _acceptLanguage());
    try {
      return await call(client);
    } on ClientError catch (e) {
      if (e is! ClientError_Api) {
        _logger.warning('Request failed: $e');
      }
      rethrow;
    }
  }
}
