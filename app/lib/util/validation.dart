import 'package:app/gen/strings.g.dart';

/// What the API checks of a user name (`validate_user_name`).
const maxUserNameLength = 64;

/// What the API checks of a password (`validate_password`).
const minPasswordLength = 8;
const maxPasswordLength = 128;

final _userNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');

/// Why the API would reject this trimmed user name and email, `null` if they are valid.
/// An empty email means none.
String? userNameOrEmailError(String userName, String email) {
  if (userName.isEmpty) {
    return t.base.user.missingUserName;
  }
  if (userName.length > maxUserNameLength || !_userNamePattern.hasMatch(userName)) {
    return t.base.user.userNameInvalid(max: maxUserNameLength);
  }
  if (email.isNotEmpty && !_isValidEmail(email)) {
    return t.base.user.emailInvalid;
  }
  return null;
}

bool _isValidEmail(String value) {
  final parts = value.split('@');
  if (parts.length < 2 || value.contains(RegExp(r'\s'))) {
    return false;
  }
  final local = parts.first;
  final domain = parts.skip(1).join('@');
  return local.isNotEmpty && domain.contains('.') && !domain.startsWith('.') && !domain.endsWith('.');
}

/// Why a password change can't be sent: a field is empty, the new password has the wrong length, or its
/// repetition differs. `null` if it can.
String? passwordChangeError({required String currentPassword, required String newPassword, required String confirmPassword}) {
  if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
    return t.base.settings.account.changePasswordDialog.fillAll;
  }
  if (newPassword.length < minPasswordLength || newPassword.length > maxPasswordLength) {
    return t.base.user.newPasswordLengthInvalid(min: minPasswordLength, max: maxPasswordLength);
  }
  if (newPassword != confirmPassword) {
    return t.base.user.passwordMismatch;
  }
  return null;
}

/// Why the API would reject this password of a new user, or one an admin sets (`validate_password`), `null` if
/// it is valid.
String? passwordError(String password) {
  if (password.isEmpty) {
    return t.base.user.missingPassword;
  }
  if (password.length < minPasswordLength || password.length > maxPasswordLength) {
    return t.base.user.passwordLengthInvalid(min: minPasswordLength, max: maxPasswordLength);
  }
  return null;
}

/// What the API checks of the profile (`validate_full_name`, `validate_first_name`, `validate_about`).
const maxFullNameLength = 100;
const maxFirstNameLength = 100;
const maxAboutLength = 1000;

/// The trimmed [value], `null` if nothing is left, like the API treats an empty field.
String? trimmedOrNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Why the API would reject this profile (the fields trimmed, `null` if empty), `null` if it is valid.
String? profileError({required String? fullName, required String? firstName, required String? about}) {
  if (fullName != null && fullName.runes.length > maxFullNameLength) {
    return t.base.settings.profile.fullNameDialog.tooLong(max: maxFullNameLength);
  }
  if (firstName != null && firstName.runes.length > maxFirstNameLength) {
    return t.base.settings.profile.firstNameDialog.tooLong(max: maxFirstNameLength);
  }
  if (about != null && about.runes.length > maxAboutLength) {
    return t.base.settings.profile.aboutDialog.tooLong(max: maxAboutLength);
  }
  return null;
}

/// What the API checks of a repository (`validate_name`, `validate_description`).
const maxRepositoryNameLength = 100;
const maxRepositoryDescriptionLength = 2000;

/// Why the API would reject this repository name and description (trimmed, the description `null` if empty),
/// `null` if they are valid.
String? repositoryError({required String name, required String? description}) {
  if (name.isEmpty) {
    return t.base.common.missingName;
  }
  if (name.runes.length > maxRepositoryNameLength) {
    return t.base.common.nameTooLong(max: maxRepositoryNameLength);
  }
  if (description != null && description.runes.length > maxRepositoryDescriptionLength) {
    return t.base.repositories.descriptionTooLong(max: maxRepositoryDescriptionLength);
  }
  return null;
}

/// `https://host/.../<owner>/<repo>.git` -> `<owner>/<repo>`, or `null` if the URL has no such path.
String? repositoryNameOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    return null;
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2) {
    return null;
  }
  final owner = segments[segments.length - 2];
  final repo = segments.last.replaceFirst(RegExp(r'\.git$'), '');
  return repo.isEmpty ? null : '$owner/$repo';
}

/// The scheme, host and port of [url] (what the API compares to tell whether a remote moved to another host),
/// `null` if it is not an absolute URL.
String? originOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
}

/// What the API checks of an LLM provider (`validate_name`, `parse_currency`) and a model (`validate_model_api_name`,
/// the display name, `validate_model_prices`).
const maxLlmProviderNameLength = 100;
const maxModelApiNameLength = 200;
const maxModelDisplayNameLength = 100;
const maxModelPrice = 100000;
const maxModelPriceDecimals = 6;

/// `max_output_tokens` is an `i32` in the API.
const maxModelOutputTokens = 2147483647;

final _currencyPattern = RegExp(r'^[A-Za-z]{3}$');
final _pricePattern = RegExp('^\\d+(\\.\\d{1,$maxModelPriceDecimals})?\$');
final _tokensPattern = RegExp(r'^\d+$');

/// Why the API would reject this LLM provider (the name trimmed, the currency trimmed, empty for none), `null` if
/// it is valid.
String? llmProviderError({required String name, required String currency}) {
  if (name.isEmpty) {
    return t.base.common.missingName;
  }
  if (name.runes.length > maxLlmProviderNameLength) {
    return t.base.common.nameTooLong(max: maxLlmProviderNameLength);
  }
  if (currency.isNotEmpty && !_currencyPattern.hasMatch(currency)) {
    return t.flutter.validation.invalidCurrency;
  }
  return null;
}

/// The price [value] as the API takes it: trimmed, with a decimal point (a comma is accepted), or `null` if it
/// is empty. Check it with [priceError] first.
String? normalizePrice(String value) => trimmedOrNull(value.replaceAll(',', '.'));

/// Whether the price [value] (empty for none) is a number up to [maxModelPrice] with at most
/// [maxModelPriceDecimals] decimals.
bool isValidPrice(String value) {
  final price = normalizePrice(value);
  if (price == null) {
    return true;
  }
  return _pricePattern.hasMatch(price) && double.parse(price) <= maxModelPrice;
}

/// Why the price [value] is invalid, `null` if it is valid or empty; shown below the field.
String? priceError(String value) =>
    isValidPrice(value) ? null : t.base.admin.llm.modelDialog.priceInvalid(max: formatMaxPrice(), decimals: maxModelPriceDecimals);

/// E.g. `100,000`.
String formatMaxPrice() => maxModelPrice.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

/// Whether [value] (empty for none) is a positive whole number of output tokens the API accepts.
bool isValidMaxOutputTokens(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return true;
  }
  final tokens = _tokensPattern.hasMatch(text) ? int.tryParse(text) : null;
  return tokens != null && tokens > 0 && tokens <= maxModelOutputTokens;
}

/// Why the API would reject this model: the API name and display name trimmed, the tokens and prices as entered
/// (empty for none; the prices are ignored without a currency, since the fields are hidden then). `null` if it
/// is valid.
String? llmModelError({
  required String apiName,
  required String displayName,
  required String maxOutputTokens,
  required bool hasCurrency,
  required String inputPrice,
  required String outputPrice,
  required String cacheReadPrice,
  required String cacheWritePrice,
}) {
  if (apiName.isEmpty) {
    return t.base.admin.llm.modelDialog.missingApiName;
  }
  if (apiName.runes.length > maxModelApiNameLength) {
    return t.base.admin.llm.modelDialog.apiNameTooLong(max: maxModelApiNameLength);
  }
  if (displayName.runes.length > maxModelDisplayNameLength) {
    return t.base.admin.llm.modelDialog.displayNameTooLong(max: maxModelDisplayNameLength);
  }
  if (!isValidMaxOutputTokens(maxOutputTokens)) {
    return t.base.admin.llm.modelDialog.maxOutputTokensInvalid;
  }
  if (!hasCurrency) {
    return null;
  }
  final prices = [inputPrice, outputPrice, cacheReadPrice, cacheWritePrice];
  if (!prices.every(isValidPrice)) {
    return t.base.admin.llm.modelDialog.pricesInvalid(max: formatMaxPrice(), decimals: maxModelPriceDecimals);
  }
  final [input, output, cacheRead, cacheWrite] = prices.map(normalizePrice).toList();
  if ((input == null) != (output == null)) {
    return t.base.admin.llm.modelDialog.inputOutputBoth;
  }
  if (input == null && (cacheRead != null || cacheWrite != null)) {
    return t.base.admin.llm.modelDialog.cacheRequiresPrices;
  }
  return null;
}
