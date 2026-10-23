import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/model/local_instance_secrets.dart';
import 'package:app/pages/home_page.dart';
import 'package:app/pages/settings/admin/llm_page.dart';
import 'package:app/pages/setup_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/local_instance_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/service/persistence_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/local.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/api_url.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

part 'account_service.mapper.dart';

final _logger = Logger('AccountService');

@MappableClass()
class AccountState with AccountStateMappable {
  /// The accounts the user is logged in with, in the order they were added.
  final List<Account> accounts;

  /// The [Account.key] of the account in use.
  final String? activeKey;

  AccountState({
    required this.accounts,
    required this.activeKey,
  });

  Account? get active => accounts.where((a) => a.key == activeKey).firstOrNull;
}

final accountProvider = ReduxProvider<AccountService, AccountState>((ref) {
  return AccountService(
    persistence: ref.read(persistenceProvider),
    api: ref.notifier(apiProvider),
    local: ref.notifier(localInstanceProvider),
    me: ref.notifier(meProvider),
    messages: ref.notifier(messageProvider),
  );
});

/// The accounts the user is logged in with, see [AccountState]. Switching the account tells the API service
/// (whose client the requests go through) and the user service (whose user the drawer and the settings show).
/// The local instance runs while there is a local account (at most one, its admin).
class AccountService extends ReduxNotifier<AccountState> {
  final PersistenceService _persistence;
  final ApiService _api;
  final LocalInstanceService _local;
  final MeService _me;
  final MessageService _messages;

  AccountService({
    required this._persistence,
    required this._api,
    required this._local,
    required this._me,
    required this._messages,
  });

  @override
  AccountState init() => AccountState(
    accounts: _persistence.getAccounts(),
    activeKey: _persistence.getActiveAccountKey(),
  );
}

/// Starts the local instance if there is a local account, before [RestoreAccountAction].
/// If it fails, the local account can't be restored, and is kept for the next start.
class RestoreLocalInstanceAction extends AsyncReduxAction<AccountService, AccountState> {
  @override
  Future<AccountState> reduce() async {
    final secrets = notifier._persistence.getLocalInstanceSecrets();
    if (secrets == null || state.accounts.every((a) => !a.isLocal)) {
      return state;
    }
    try {
      await external(notifier._local).dispatchAsync(StartLocalInstanceAction(secrets));
    } on LocalError catch (e) {
      _logger.warning('Cannot start the local instance: ${e.message}');
    }
    return state;
  }
}

/// Sends the API requests for the active account (the first one if none is set).
/// Returns it, or `null` if the user needs to log in (also if the stored account is unusable).
class RestoreAccountAction extends ReduxActionWithResult<AccountService, AccountState, Account?> {
  @override
  (AccountState, Account?) reduce() {
    final account = state.active ?? state.accounts.firstOrNull;
    try {
      external(notifier._api).dispatch(ApiSetAccountAction(account));
    } on ClientError catch (e) {
      _logger.warning('Cannot restore $account: $e');
      return (state, null);
    }
    // In the background, the pages show the account's user name until then.
    unawaited(external(notifier._me).dispatchAsync(RefreshMeAction()));
    return (state.copyWith(activeKey: account?.key), account);
  }
}

/// Logs in on the server at [apiUrl], adds the account (or replaces the same user's) and switches to it.
/// Shows a snack bar if it fails.
class LoginAction extends AsyncReduxAction<AccountService, AccountState> with GlobalActions {
  final String apiUrl;
  final String userNameOrEmail;
  final String password;

  LoginAction({
    required this.apiUrl,
    required this.userNameOrEmail,
    required this.password,
  });

  @override
  Future<AccountState> reduce() async {
    final url = normalizeApiUrl(apiUrl);
    if (url == null) {
      global.dispatch(ShowSnackBarAction(message: t.flutter.account.invalidApiUrl));
      return state;
    }

    try {
      final (account, user) = await external(notifier._api).dispatchAsyncTakeResult(
        ApiLoginAction(
          apiUrl: url,
          userNameOrEmail: userNameOrEmail.trim(),
          password: password,
        ),
      );
      await dispatchAsync(SwitchAccountAction(account, user: user));
    } on ClientError catch (e) {
      global.dispatch(
        ShowSnackBarAction(
          message: e.code == ErrorCode.unauthorized ? t.base.login.wrongCredentials : t.base.login.loginFailed(error: e.userMessage),
        ),
      );
    }

    return state;
  }
}

/// Starts the local instance (creating it on the first start), logs in as its admin, adds the account (or replaces
/// the stored one) and switches to it. After the first start, opens the LLM settings, since the instance has no
/// model yet. Shows a snack bar if it fails.
class CreateLocalAccountAction extends AsyncReduxAction<AccountService, AccountState> with GlobalActions {
  @override
  Future<AccountState> reduce() async {
    final created = notifier._persistence.getLocalInstanceSecrets() == null;
    try {
      final (account, user) = await dispatchAsyncTakeResult(_LocalLoginAction());
      await dispatchAsync(SwitchAccountAction(account, user: user));
    } on LocalError catch (e) {
      global.dispatch(ShowSnackBarAction(message: t.flutter.account.localStartFailed(message: e.message)));
      return state;
    } on ClientError catch (e) {
      global.dispatch(ShowSnackBarAction(message: t.base.login.loginFailed(error: e.userMessage)));
      return state;
    }

    if (created) {
      // On top of the home page, which the switch opened.
      unawaited(global.dispatchAsync(NavigateAction.push(const LlmPage())));
    }
    return state;
  }
}

/// Starts the local instance and logs in as its admin with the stored secrets, generating them on the first start.
/// Returns the account with its user, without adding it. Throws [LocalError] or [ClientError] if it fails.
class _LocalLoginAction extends AsyncReduxActionWithResult<AccountService, AccountState, (Account, UserDto)> {
  @override
  Future<(AccountState, (Account, UserDto))> reduce() async {
    var secrets = notifier._persistence.getLocalInstanceSecrets();
    if (secrets == null) {
      secrets = LocalInstanceSecrets(
        tokenEncryptionKey: generateSecret(),
        userName: localAdminUserName(),
        password: generateSecret(),
      );
      // Before the start, so the key of the database is never lost.
      await notifier._persistence.setLocalInstanceSecrets(secrets);
    }

    await external(notifier._local).dispatchAsync(StartLocalInstanceAction(secrets));
    final result = await external(notifier._api).dispatchAsyncTakeResult(
      ApiLoginAction(apiUrl: null, userNameOrEmail: secrets.userName, password: secrets.password),
    );
    return (state, result);
  }
}

/// Uses [account] from now on (adding it, or replacing the stored one of the same user)
/// and opens the home page. [user] is the account's user if it is known already (from the login), else it is
/// loaded.
class SwitchAccountAction extends AsyncReduxAction<AccountService, AccountState> with GlobalActions {
  final Account account;
  final UserDto? user;

  SwitchAccountAction(this.account, {this.user});

  @override
  Future<AccountState> reduce() async {
    final accounts = [
      for (final a in state.accounts) a.key == account.key ? account : a,
      if (state.accounts.every((a) => a.key != account.key)) account,
    ];
    await notifier._persistence.setAccounts(accounts);
    await notifier._persistence.setActiveAccountKey(account.key);
    // Its stream would subscribe again with the new account's client.
    external(notifier._messages).dispatch(StopFollowMessageAction());
    external(notifier._api).dispatch(ApiSetAccountAction(account));
    external(notifier._me).dispatch(SetMeAction(user));
    if (user == null) {
      unawaited(external(notifier._me).dispatchAsync(RefreshMeAction()));
    }

    return state.copyWith(
      accounts: accounts,
      activeKey: account.key,
    );
  }

  @override
  void after() {
    super.after();
    // ignore: discarded_futures
    global.dispatchAsync(NavigateAction.pushRoot(const HomePage()));
  }
}

/// Stores the new user name of the active account, e.g. after the user changed it, which the account list shows.
class SetAccountUserNameAction extends AsyncReduxAction<AccountService, AccountState> {
  final String userName;

  SetAccountUserNameAction(this.userName);

  @override
  Future<AccountState> reduce() async {
    final accounts = [
      for (final a in state.accounts) a.key == state.activeKey ? a.copyWith(user: a.user.copyWith(userName: userName)) : a,
    ];
    await notifier._persistence.setAccounts(accounts);
    final secrets = notifier._persistence.getLocalInstanceSecrets();
    if ((state.active?.isLocal ?? false) && secrets != null) {
      // To log in with it again, see [_LocalLoginAction].
      await notifier._persistence.setLocalInstanceSecrets(secrets.copyWith(userName: userName));
    }
    return state.copyWith(accounts: accounts);
  }
}

/// Stores the new password of the active account if it is the local one, to log in with it again after the account
/// was removed (see [CreateLocalAccountAction]). Dispatched after the password changed.
class SetLocalPasswordAction extends AsyncGlobalAction {
  final String password;

  SetLocalPasswordAction(this.password);

  @override
  Future<void> reduce() async {
    final persistence = ref.read(persistenceProvider);
    final secrets = persistence.getLocalInstanceSecrets();
    if ((ref.read(accountProvider).active?.isLocal ?? false) && secrets != null) {
      await persistence.setLocalInstanceSecrets(secrets.copyWith(password: password));
    }
  }

  /// Without the password, which the debug observers would print otherwise.
  @override
  String toString() => 'SetLocalPasswordAction()';
}

/// Logs out of the active account and removes it.
/// Switches to the next account, or opens the setup page if there is none.
class LogoutAction extends AsyncReduxAction<AccountService, AccountState> {
  @override
  Future<AccountState> reduce() async {
    final account = state.active;
    if (account == null) {
      return state;
    }

    try {
      await external(notifier._api).dispatchAsync(ApiLogoutAction(account: account));
    } on ClientError catch (e) {
      // The session expires on the server anyway.
      _logger.warning('Logout failed: $e');
    }

    return await dispatchAsync(_RemoveAccountAction(account));
  }
}

/// Removes the account whose session ended, e.g. after 30 days without use or when an admin disabled the user,
/// and tells the user to log in again. Dispatched by the API service when a request fails with `UNAUTHORIZED`.
class SessionExpiredAction extends AsyncGlobalAction {
  final Account account;

  SessionExpiredAction(this.account);

  @override
  Future<void> reduce() async {
    if (ref.read(accountProvider).accounts.every((a) => a.key != account.key || a.token != account.token)) {
      // Removed already (e.g. by another request that failed), or logged in again since.
      return;
    }

    await ref.redux(accountProvider).dispatchAsync(_RemoveAccountAction(account));
    ref.global.dispatch(ShowSnackBarAction(message: t.flutter.account.sessionExpired(server: account.server)));
  }

  @override
  String toString() => 'SessionExpiredAction($account)';
}

/// Removes [account] and drops its client.
/// If it was the active one, switches to the next account, or opens the setup page if there is none.
class _RemoveAccountAction extends AsyncReduxAction<AccountService, AccountState> with GlobalActions {
  final Account account;

  _RemoveAccountAction(this.account);

  bool _wasActive = false;

  @override
  Future<AccountState> reduce() async {
    if (state.accounts.every((a) => a.key != account.key)) {
      return state;
    }

    _wasActive = account.key == state.activeKey;
    final accounts = state.accounts.where((a) => a.key != account.key).toList();
    final active = _wasActive ? accounts.firstOrNull : state.active;
    await notifier._persistence.setAccounts(accounts);
    await notifier._persistence.setActiveAccountKey(active?.key);
    if (_wasActive) {
      // Its stream would subscribe again with the next account's client, or with none.
      external(notifier._messages).dispatch(StopFollowMessageAction());
    }
    external(notifier._api).dispatch(ApiSetAccountAction(active));
    if (_wasActive) {
      external(notifier._me).dispatch(SetMeAction(null));
      unawaited(external(notifier._me).dispatchAsync(RefreshMeAction()));
    }
    if (account.isLocal) {
      // Its data stays, to log in again with the stored secrets, see [CreateLocalAccountAction].
      await external(notifier._local).dispatchAsync(StopLocalInstanceAction());
    }

    return state.copyWith(
      accounts: accounts,
      activeKey: active?.key,
    );
  }

  @override
  void after() {
    super.after();
    if (_wasActive) {
      // ignore: discarded_futures
      global.dispatchAsync(NavigateAction.pushRoot(state.active == null ? const SetupPage() : const HomePage()));
    }
  }

  @override
  String toString() => '_RemoveAccountAction($account)';
}
