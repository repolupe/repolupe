part of '../api_service.dart';

/// Logs in on the server at [apiUrl], or on the local instance if it is `null`, and returns the account with its
/// user.
class ApiLoginAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, (Account, UserDto)> {
  final String? apiUrl;
  final String userNameOrEmail;
  final String password;

  ApiLoginAction({
    required this.apiUrl,
    required this.userNameOrEmail,
    required this.password,
  });

  @override
  Future<(AccountClient?, (Account, UserDto))> reduce() async {
    final response = await dispatchAsyncTakeResult(
      _ApiCallAction(
        client: _newClient(apiUrl, notifier._local.state),
        call: (client) => client.login(
          request: LoginRequest(userNameOrEmail: userNameOrEmail, password: password),
        ),
      ),
    );
    return (state, (Account.fromLogin(apiUrl: apiUrl, response: response), response.user));
  }

  @override
  String toString() => 'ApiLoginAction(apiUrl: $apiUrl, userNameOrEmail: $userNameOrEmail)';
}

/// Deletes the session of [account] on its server.
class ApiLogoutAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final Account account;

  ApiLogoutAction({required this.account});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        account: account,
        call: (client) => client.logout(),
        // The account is removed anyway.
        expireOnUnauthorized: false,
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiLogoutAction($account)';
}

/// Loads the logged-in user.
class ApiGetMeAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, UserDto> {
  ApiGetMeAction();

  @override
  Future<(AccountClient?, UserDto)> reduce() async {
    final user = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.me(),
      ),
    );
    return (state, user);
  }
}

/// Loads the instance, i.e. the server's name.
class ApiGetInstanceAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, InstanceDto> {
  ApiGetInstanceAction();

  @override
  Future<(AccountClient?, InstanceDto)> reduce() async {
    final instance = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.instance(),
      ),
    );
    return (state, instance);
  }
}
