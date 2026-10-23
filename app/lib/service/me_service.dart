import 'package:app/gen/strings.g.dart';
import 'package:app/model/account.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/validation.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('MeService');

final meProvider = ReduxProvider<MeService, UserDto?>((ref) {
  return MeService(api: ref.notifier(apiProvider));
});

/// The user of the active account (`GET /api/v1/me`), `null` without an account or until it is loaded.
/// The account service sets it when the account changes (from the login, else with [RefreshMeAction]), and the
/// actions that change the user refresh it, so the drawer, the settings and `HomePage` see the change.
class MeService extends ReduxNotifier<UserDto?> {
  final ApiService _api;

  MeService({required this._api});

  @override
  UserDto? init() => null;
}

/// Sets the user, e.g. the one of the login response, or `null` when the account is removed.
class SetMeAction extends ReduxAction<MeService, UserDto?> {
  final UserDto? user;

  SetMeAction(this.user);

  @override
  UserDto? reduce() => user;

  @override
  String toString() => 'SetMeAction(${user?.userName})';
}

/// Loads the user of the active account again, keeping the previous one if that fails (`null` without an account).
class RefreshMeAction extends AsyncReduxAction<MeService, UserDto?> {
  @override
  Future<UserDto?> reduce() async {
    final client = notifier._api.state;
    if (client == null) {
      return null;
    }

    try {
      final user = await external(notifier._api).dispatchAsyncTakeResult(ApiGetMeAction());
      // Dropped if the account changed in the meantime.
      return notifier._api.state == client ? user : state;
    } on ClientError catch (e) {
      _logger.warning('Cannot load the user: $e');
      return state;
    }
  }
}

/// Loads the user again after a request of [account] failed with `PASSWORD_CHANGE_REQUIRED`, so that
/// `HomePage` shows the page to change it (e.g. an admin required it since the user was loaded).
/// Dispatched by the API service.
class PasswordChangeRequiredAction extends AsyncGlobalAction {
  final Account account;

  PasswordChangeRequiredAction(this.account);

  @override
  Future<void> reduce() async {
    if (ref.read(apiProvider)?.account != account || (ref.read(meProvider)?.mustChangePassword ?? false)) {
      // Not the active account, or known already (e.g. by another request that failed).
      return;
    }
    await ref.redux(meProvider).dispatchAsync(RefreshMeAction());
  }

  @override
  String toString() => 'PasswordChangeRequiredAction($account)';
}

/// Changes the password of the active account, which signs out its other sessions, after checking the new one
/// and its repetition. Returns why that failed, `null` if it succeeded (with a snack bar then). Loads the user
/// again, which ends a required password change.
class ChangePasswordAction extends AsyncReduxActionWithResult<MeService, UserDto?, String?> with GlobalActions {
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;

  ChangePasswordAction({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  @override
  Future<(UserDto?, String?)> reduce() async {
    final error = passwordChangeError(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    if (error != null) {
      return (state, error);
    }

    try {
      await external(notifier._api).dispatchAsync(
        ApiChangePasswordAction(currentPassword: currentPassword, newPassword: newPassword),
      );
    } on ClientError catch (e) {
      return (
        state,
        switch (e.code) {
          ErrorCode.wrongPassword => t.base.user.wrongPassword,
          ErrorCode.samePassword => t.base.user.samePassword,
          _ => t.base.settings.account.page.changePasswordFailed(error: e.userMessage),
        },
      );
    }

    await global.dispatchAsync(SetLocalPasswordAction(newPassword));
    await dispatchAsync(RefreshMeAction());
    global.dispatch(ShowSnackBarAction(message: t.base.settings.account.page.passwordChanged));
    return (state, null);
  }

  /// Without the passwords, which the debug observers would print otherwise.
  @override
  String toString() => 'ChangePasswordAction()';
}

/// Changes the user name and email of the active account after checking them (an empty email removes it).
/// Returns why that failed, `null` if it succeeded (with a snack bar then). Updates the user and the stored
/// account, which the account list shows by its user name.
class UpdateIdentityAction extends AsyncGlobalActionWithResult<String?> {
  final String userName;
  final String email;

  UpdateIdentityAction({required this.userName, required this.email});

  @override
  Future<String?> reduce() async {
    final userName = this.userName.trim();
    final email = this.email.trim();
    final error = userNameOrEmailError(userName, email);
    if (error != null) {
      return error;
    }

    final UserDto user;
    try {
      user = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiUpdateIdentityAction(userName: userName, email: email.isEmpty ? null : email));
    } on ClientError catch (e) {
      return switch (e.code) {
        ErrorCode.userNameTaken => t.base.user.userNameTaken,
        ErrorCode.emailTaken => t.base.user.emailTaken,
        _ => t.base.settings.account.page.identitySaveFailed(error: e.userMessage),
      };
    }

    ref.redux(meProvider).dispatch(SetMeAction(user));
    await ref.redux(accountProvider).dispatchAsync(SetAccountUserNameAction(user.userName));
    ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.account.page.identitySaved));
    return null;
  }

  @override
  String toString() => 'UpdateIdentityAction(userName: $userName, email: $email)';
}

/// Replaces the profile of the active account, which the assistant is told about the user, after checking the
/// lengths; an empty field is cleared. Returns why that failed, `null` if it succeeded (with a snack bar then).
class UpdateProfileAction extends AsyncGlobalActionWithResult<String?> {
  final String fullName;
  final String firstName;
  final String about;

  UpdateProfileAction({required this.fullName, required this.firstName, required this.about});

  @override
  Future<String?> reduce() async {
    final fullName = trimmedOrNull(this.fullName);
    final firstName = trimmedOrNull(this.firstName);
    final about = trimmedOrNull(this.about);
    final error = profileError(fullName: fullName, firstName: firstName, about: about);
    if (error != null) {
      return error;
    }

    try {
      await ref.redux(apiProvider).dispatchAsync(ApiUpdateProfileAction(fullName: fullName, firstName: firstName, about: about));
    } on ClientError catch (e) {
      return t.base.settings.profile.page.saveFailed(error: e.userMessage);
    }

    await ref.redux(meProvider).dispatchAsync(RefreshMeAction());
    ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.profile.page.updated));
    return null;
  }

  @override
  String toString() => 'UpdateProfileAction(fullName: $fullName, firstName: $firstName)';
}

/// What [SetDefaultModelAction] did.
enum SetDefaultModelResult {
  saved,

  /// The model no longer exists (e.g. an admin deleted it), so the models should be loaded again.
  unknownModel,
  failed,
}

/// Sets the model of the active account, `null` for the default model. Shows a snack bar in any case.
class SetDefaultModelAction extends AsyncGlobalActionWithResult<SetDefaultModelResult> {
  final UuidValue? modelId;

  SetDefaultModelAction(this.modelId);

  @override
  Future<SetDefaultModelResult> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiSetMyDefaultModelAction(modelId: modelId));
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.preferences.page.modelSaveFailed(error: e.userMessage)));
      return e.code == ErrorCode.unknownModel ? SetDefaultModelResult.unknownModel : SetDefaultModelResult.failed;
    }

    await ref.redux(meProvider).dispatchAsync(RefreshMeAction());
    ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.preferences.page.modelUpdated));
    return SetDefaultModelResult.saved;
  }

  @override
  String toString() => 'SetDefaultModelAction($modelId)';
}

/// Sets the language of the active account (a BCP 47 tag), `null` for the device's languages. Shows a snack bar
/// and returns `false` if that fails.
class SetLocaleAction extends AsyncGlobalActionWithResult<bool> {
  final String? locale;

  SetLocaleAction(this.locale);

  @override
  Future<bool> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiSetLocaleAction(locale: locale));
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.preferences.page.languageSaveFailed(error: e.userMessage)));
      return false;
    }

    await ref.redux(meProvider).dispatchAsync(RefreshMeAction());
    ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.preferences.page.languageUpdated));
    return true;
  }

  @override
  String toString() => 'SetLocaleAction($locale)';
}

/// Sets whether the changes the model proposes are committed as soon as its answer is complete. Shows a snack bar
/// and returns `false` if that fails.
class SetAutoCommitAction extends AsyncGlobalActionWithResult<bool> {
  final bool autoCommit;

  SetAutoCommitAction(this.autoCommit);

  @override
  Future<bool> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiSetAutoCommitAction(autoCommit: autoCommit));
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.preferences.page.autoCommitSaveFailed(error: e.userMessage)));
      return false;
    }

    await ref.redux(meProvider).dispatchAsync(RefreshMeAction());
    ref.global.dispatch(
      ShowSnackBarAction(
        message: autoCommit ? t.base.settings.preferences.page.autoCommitOn : t.base.settings.preferences.page.autoCommitOff,
      ),
    );
    return true;
  }

  @override
  String toString() => 'SetAutoCommitAction($autoCommit)';
}
