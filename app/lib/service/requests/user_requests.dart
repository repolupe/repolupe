part of '../api_service.dart';

/// Changes the user name and email of the logged-in user and returns the user.
class ApiUpdateIdentityAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, UserDto> {
  final String userName;

  /// `null` removes it.
  final String? email;

  ApiUpdateIdentityAction({required this.userName, required this.email});

  @override
  Future<(AccountClient?, UserDto)> reduce() async {
    final user = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.updateIdentity(
          request: UpdateIdentityRequest(userName: userName, email: email),
        ),
      ),
    );
    return (state, user);
  }

  @override
  String toString() => 'ApiUpdateIdentityAction(userName: $userName, email: $email)';
}

/// Changes the password of the logged-in user, which signs out their other sessions.
/// Also while a password change is required.
class ApiChangePasswordAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final String currentPassword;
  final String newPassword;

  ApiChangePasswordAction({required this.currentPassword, required this.newPassword});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.changePassword(
          request: ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword),
        ),
      ),
    );
    return state;
  }

  /// Without the passwords, which the debug observers would print otherwise.
  @override
  String toString() => 'ApiChangePasswordAction()';
}

/// Replaces the profile of the logged-in user, which the LLM is told about them. `null` clears a field.
class ApiUpdateProfileAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final String? fullName;
  final String? firstName;
  final String? about;

  ApiUpdateProfileAction({required this.fullName, required this.firstName, required this.about});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.updateProfile(
          request: UpdateProfileRequest(fullName: fullName, firstName: firstName, about: about),
        ),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiUpdateProfileAction(fullName: $fullName, firstName: $firstName)';
}

/// Sets the model of the logged-in user, `null` for the default model.
class ApiSetMyDefaultModelAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue? modelId;

  ApiSetMyDefaultModelAction({required this.modelId});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.setMyDefaultModel(request: SetMyDefaultModelRequest(modelId: modelId)),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiSetMyDefaultModelAction(modelId: $modelId)';
}

/// Sets the language of the logged-in user (a BCP 47 tag), `null` for the device's languages.
class ApiSetLocaleAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final String? locale;

  ApiSetLocaleAction({required this.locale});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.setLocale(request: SetLocaleRequest(locale: locale)),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiSetLocaleAction(locale: $locale)';
}

/// Sets whether the changes the model proposes to the logged-in user are committed as soon as its answer is
/// complete.
class ApiSetAutoCommitAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final bool autoCommit;

  ApiSetAutoCommitAction({required this.autoCommit});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.setMyAutoCommit(request: SetAutoCommitRequest(autoCommit: autoCommit)),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiSetAutoCommitAction(autoCommit: $autoCommit)';
}
