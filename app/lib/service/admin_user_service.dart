import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/validation.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

// What admins do to other users (`/api/v1/users`, `/register`, `/delete-user`): each action checks the input,
// calls the API, shows a snack bar in any case, and returns the result (`null` or `false` if it failed).

/// The text for a failed request about a user: the taken user name or email, else [fallback] with the API's message.
String _userErrorMessage(ClientError e, String Function({required Object error}) fallback) => switch (e.code) {
  ErrorCode.userNameTaken => t.base.user.userNameTaken,
  ErrorCode.emailTaken => t.base.user.emailTaken,
  _ => fallback(error: e.userMessage),
};

/// Creates a user after checking the user name, email (empty for none) and password. Returns the user, `null` if
/// that failed.
class CreateUserAction extends AsyncGlobalActionWithResult<UserDto?> {
  final String userName;
  final String email;
  final String password;

  /// The user must change the password after logging in with this one.
  final bool mustChangePassword;

  CreateUserAction({required this.userName, required this.email, required this.password, required this.mustChangePassword});

  @override
  Future<UserDto?> reduce() async {
    final userName = this.userName.trim();
    final email = this.email.trim();
    final error = userNameOrEmailError(userName, email) ?? passwordError(password);
    if (error != null) {
      ref.global.dispatch(ShowSnackBarAction(message: error));
      return null;
    }

    final UserDto user;
    try {
      user = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(
            ApiRegisterUserAction(
              request: RegisterRequest(userName: userName, email: trimmedOrNull(email), password: password, mustChangePassword: mustChangePassword),
            ),
          );
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: _userErrorMessage(e, t.base.admin.users.page.createFailed)));
      return null;
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.users.page.created));
    return user;
  }

  /// Without the password, which the debug observers would print otherwise.
  @override
  String toString() => 'CreateUserAction(userName: $userName, email: $email)';
}

/// Replaces the user name, email (empty for none) and permissions of the user [id] after checking them. For the
/// active account's own user, the loaded user and the stored account follow (if they must change their password
/// now, `HomePage` closes the settings). Returns the user, `null` if that failed.
class UpdateUserAction extends AsyncGlobalActionWithResult<UserDto?> {
  final UuidValue id;
  final String userName;
  final String email;
  final bool canLogin;
  final bool canManageRepositories;
  final bool canChangeIdentity;
  final bool mustChangePassword;

  UpdateUserAction({
    required this.id,
    required this.userName,
    required this.email,
    required this.canLogin,
    required this.canManageRepositories,
    required this.canChangeIdentity,
    required this.mustChangePassword,
  });

  @override
  Future<UserDto?> reduce() async {
    final userName = this.userName.trim();
    final email = this.email.trim();
    final error = userNameOrEmailError(userName, email);
    if (error != null) {
      ref.global.dispatch(ShowSnackBarAction(message: error));
      return null;
    }

    final UserDto user;
    try {
      user = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(
            ApiUpdateUserAction(
              id: id,
              request: UpdateUserRequest(
                userName: userName,
                email: trimmedOrNull(email),
                canLogin: canLogin,
                canManageRepositories: canManageRepositories,
                canChangeIdentity: canChangeIdentity,
                mustChangePassword: mustChangePassword,
              ),
            ),
          );
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: _userErrorMessage(e, t.base.admin.users.page.saveFailed)));
      return null;
    }

    if (ref.read(meProvider)?.id == user.id) {
      ref.redux(meProvider).dispatch(SetMeAction(user));
      await ref.redux(accountProvider).dispatchAsync(SetAccountUserNameAction(user.userName));
    }
    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.users.page.updated));
    return user;
  }

  @override
  String toString() => 'UpdateUserAction(id: $id, userName: $userName, email: $email)';
}

/// What [SetUserPasswordAction] did: the updated user, or why it failed (shown in the dialog, which stays open).
typedef SetUserPasswordResult = ({UserDto? user, String? error});

/// Sets the password of the user [id] after checking it, which signs them out everywhere. Shows a snack bar if it
/// succeeded.
class SetUserPasswordAction extends AsyncGlobalActionWithResult<SetUserPasswordResult> {
  final UuidValue id;
  final String password;

  /// The user must change the password after logging in with this one.
  final bool mustChangePassword;

  SetUserPasswordAction({required this.id, required this.password, required this.mustChangePassword});

  @override
  Future<SetUserPasswordResult> reduce() async {
    final error = passwordError(password);
    if (error != null) {
      return (user: null, error: error);
    }

    final UserDto user;
    try {
      user = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(
            ApiResetPasswordAction(
              id: id,
              request: ResetPasswordRequest(password: password, mustChangePassword: mustChangePassword),
            ),
          );
    } on ClientError catch (e) {
      return (user: null, error: t.base.admin.users.page.setPasswordFailed(error: e.userMessage));
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.users.page.passwordSet));
    return (user: user, error: null);
  }

  /// Without the password, which the debug observers would print otherwise.
  @override
  String toString() => 'SetUserPasswordAction(id: $id, mustChangePassword: $mustChangePassword)';
}

/// Deletes the user [id] with their sessions, chats and repositories. Returns why that failed, `null` if it was
/// deleted (with a snack bar then).
class DeleteUserAction extends AsyncGlobalActionWithResult<String?> {
  final UuidValue id;

  DeleteUserAction(this.id);

  @override
  Future<String?> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiDeleteUserAction(id: id));
    } on ClientError catch (e) {
      return t.base.admin.users.page.deleteFailed(error: e.userMessage);
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.users.page.deleted));
    return null;
  }

  @override
  String toString() => 'DeleteUserAction($id)';
}
