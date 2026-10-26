///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element

class Translations with BaseTranslations<AppLocale, Translations> {
  /// Returns the current translations of the given [context].
  ///
  /// Usage:
  /// final t = Translations.of(context);
  static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  Translations({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.en,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           );

  /// Metadata for the translations of <en>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final Translations _root = this; // ignore: unused_field

  Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

  // Translations
  late final Translations$base$en base = Translations$base$en.internal(_root);
  late final Translations$flutter$en flutter = Translations$flutter$en.internal(_root);
}

// Path: base
class Translations$base$en {
  Translations$base$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$base$common$en common = Translations$base$common$en.internal(_root);
  late final Translations$base$errors$en errors = Translations$base$errors$en.internal(_root);
  late final Translations$base$status$en status = Translations$base$status$en.internal(_root);
  late final Translations$base$user$en user = Translations$base$user$en.internal(_root);
  late final Translations$base$app$en app = Translations$base$app$en.internal(_root);
  late final Translations$base$login$en login = Translations$base$login$en.internal(_root);
  late final Translations$base$chat$en chat = Translations$base$chat$en.internal(_root);
  late final Translations$base$settings$en settings = Translations$base$settings$en.internal(_root);
  late final Translations$base$repositories$en repositories = Translations$base$repositories$en.internal(_root);
  late final Translations$base$documents$en documents = Translations$base$documents$en.internal(_root);
  late final Translations$base$admin$en admin = Translations$base$admin$en.internal(_root);
}

// Path: flutter
class Translations$flutter$en {
  Translations$flutter$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$common$en common = Translations$flutter$common$en.internal(_root);
  late final Translations$flutter$setup$en setup = Translations$flutter$setup$en.internal(_root);
  late final Translations$flutter$account$en account = Translations$flutter$account$en.internal(_root);
  late final Translations$flutter$chat$en chat = Translations$flutter$chat$en.internal(_root);
  late final Translations$flutter$settings$en settings = Translations$flutter$settings$en.internal(_root);
  late final Translations$flutter$validation$en validation = Translations$flutter$validation$en.internal(_root);
  late final Translations$flutter$themeMode$en themeMode = Translations$flutter$themeMode$en.internal(_root);
  late final Translations$flutter$repositories$en repositories = Translations$flutter$repositories$en.internal(_root);
  late final Translations$flutter$documents$en documents = Translations$flutter$documents$en.internal(_root);
  late final Translations$flutter$format$en format = Translations$flutter$format$en.internal(_root);
  late final Translations$flutter$admin$en admin = Translations$flutter$admin$en.internal(_root);
}

// Path: base.common
class Translations$base$common$en {
  Translations$base$common$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Save'
  String get save => 'Save';

  /// en: 'Cancel'
  String get cancel => 'Cancel';

  /// en: 'Delete'
  String get delete => 'Delete';

  /// en: 'Close'
  String get close => 'Close';

  /// en: 'Edit'
  String get edit => 'Edit';

  /// en: 'Retry'
  String get retry => 'Retry';

  /// en: 'Search'
  String get search => 'Search';

  /// en: 'Refresh'
  String get refresh => 'Refresh';

  /// en: 'Download'
  String get download => 'Download';

  /// en: 'Name'
  String get name => 'Name';

  /// en: 'Model'
  String get model => 'Model';

  /// en: 'Status'
  String get status => 'Status';

  /// en: 'Error'
  String get error => 'Error';

  /// en: 'Unknown error'
  String get unknownError => 'Unknown error';

  /// en: 'Required.'
  String get required => 'Required.';

  /// en: 'Loading...'
  String get loading => 'Loading...';

  /// en: 'Actions'
  String get actions => 'Actions';

  /// en: 'Default'
  String get kDefault => 'Default';

  /// en: 'Added'
  String get added => 'Added';

  /// en: 'Repository'
  String get repository => 'Repository';

  /// en: 'Input'
  String get input => 'Input';

  /// en: 'Output'
  String get output => 'Output';

  /// en: 'Missing name'
  String get missingName => 'Missing name';

  /// en: 'Name must be at most {max} characters long'
  String nameTooLong({required Object max}) => 'Name must be at most ${max} characters long';
}

// Path: base.errors
class Translations$base$errors$en {
  Translations$base$errors$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Unexpected response from the server ({status}).'
  String invalidResponse({required Object status}) => 'Unexpected response from the server (${status}).';

  /// en: 'Could not reach the server.'
  String get unreachable => 'Could not reach the server.';

  /// en: 'An error occurred on the server.'
  String get internalError => 'An error occurred on the server.';

  /// en: 'The request is invalid.'
  String get validationError => 'The request is invalid.';

  /// en: 'The request has an unsupported format.'
  String get unsupportedMediaType => 'The request has an unsupported format.';

  /// en: 'You are not logged in.'
  String get unauthorized => 'You are not logged in.';

  /// en: 'You are not allowed to do this.'
  String get forbidden => 'You are not allowed to do this.';

  /// en: 'Not found, it may have been deleted.'
  String get notFound => 'Not found, it may have been deleted.';

  /// en: 'It was changed at the same time, please try again.'
  String get conflict => 'It was changed at the same time, please try again.';

  /// en: 'Too many requests, please try again later.'
  String get rateLimited => 'Too many requests, please try again later.';

  /// en: 'A user with this user name already exists.'
  String get userNameTaken => 'A user with this user name already exists.';

  /// en: 'A user with this email already exists.'
  String get emailTaken => 'A user with this email already exists.';

  /// en: 'This name is already taken.'
  String get nameTaken => 'This name is already taken.';

  /// en: 'The repository was not found on the remote.'
  String get repoNotFound => 'The repository was not found on the remote.';

  /// en: 'The branch was not found on the remote.'
  String get branchNotFound => 'The branch was not found on the remote.';

  /// en: 'The credentials were rejected, check the access token or API key.'
  String get authFailed => 'The credentials were rejected, check the access token or API key.';

  /// en: 'The host changed, so the stored token or API key cannot be kept. Set a new one, or remove it.'
  String get tokenRequired => 'The host changed, so the stored token or API key cannot be kept. Set a new one, or remove it.';

  /// en: 'Could not reach the remote server, or it responded with an error.'
  String get remoteUnreachable => 'Could not reach the remote server, or it responded with an error.';

  /// en: 'A repository no longer exists.'
  String get unknownRepository => 'A repository no longer exists.';

  /// en: 'There is no user with this user name or email.'
  String get unknownUser => 'There is no user with this user name or email.';

  /// en: 'An answer is already being generated in this chat.'
  String get generationInProgress => 'An answer is already being generated in this chat.';

  /// en: 'Only a failed or cancelled answer at the end of the chat can be retried.'
  String get notRetryable => 'Only a failed or cancelled answer at the end of the chat can be retried.';

  /// en: 'The current password is incorrect.'
  String get wrongPassword => 'The current password is incorrect.';

  /// en: 'The new password must differ from the current one.'
  String get samePassword => 'The new password must differ from the current one.';

  /// en: 'You must change your password first.'
  String get passwordChangeRequired => 'You must change your password first.';

  /// en: 'The model is no longer available.'
  String get unknownModel => 'The model is no longer available.';

  /// en: 'No language model is configured, ask an admin to add one.'
  String get noModelConfigured => 'No language model is configured, ask an admin to add one.';

  /// en: 'The server is unavailable, please try again later.'
  String get unavailable => 'The server is unavailable, please try again later.';

  /// en: 'The file is no longer available.'
  String get fileUnavailable => 'The file is no longer available.';

  /// en: 'The attachment does not exist or was sent already.'
  String get unknownAttachment => 'The attachment does not exist or was sent already.';
}

// Path: base.status
class Translations$base$status$en {
  Translations$base$status$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Pending'
  String get pending => 'Pending';

  /// en: 'Syncing'
  String get syncing => 'Syncing';

  /// en: 'Ready'
  String get ready => 'Ready';

  /// en: 'Failed'
  String get failed => 'Failed';

  /// en: 'Waiting'
  String get waiting => 'Waiting';

  /// en: 'Converting'
  String get converting => 'Converting';

  /// en: 'Not available'
  String get notAvailable => 'Not available';

  /// en: 'Converted'
  String get converted => 'Converted';
}

// Path: base.user
class Translations$base$user$en {
  Translations$base$user$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'User name'
  String get userName => 'User name';

  /// en: 'Email'
  String get email => 'Email';

  /// en: 'Email (optional)'
  String get emailOptional => 'Email (optional)';

  /// en: 'User name or email'
  String get userNameOrEmail => 'User name or email';

  /// en: 'Password'
  String get password => 'Password';

  /// en: '{min} to {max} characters'
  String passwordHint({required Object min, required Object max}) => '${min} to ${max} characters';

  /// en: 'Current password'
  String get currentPassword => 'Current password';

  /// en: 'New password'
  String get newPassword => 'New password';

  /// en: 'Confirm new password'
  String get confirmPassword => 'Confirm new password';

  /// en: 'Missing password'
  String get missingPassword => 'Missing password';

  /// en: 'Password must be {min} to {max} characters long'
  String passwordLengthInvalid({required Object min, required Object max}) => 'Password must be ${min} to ${max} characters long';

  /// en: 'The new password must be {min} to {max} characters long.'
  String newPasswordLengthInvalid({required Object min, required Object max}) => 'The new password must be ${min} to ${max} characters long.';

  /// en: 'New passwords do not match.'
  String get passwordMismatch => 'New passwords do not match.';

  /// en: 'Current password is incorrect'
  String get wrongPassword => 'Current password is incorrect';

  /// en: 'The new password must differ from the current one'
  String get samePassword => 'The new password must differ from the current one';

  /// en: 'Role'
  String get role => 'Role';

  /// en: 'Admin'
  String get roleAdmin => 'Admin';

  /// en: 'User'
  String get roleUser => 'User';

  /// en: 'Missing user name'
  String get missingUserName => 'Missing user name';

  /// en: 'User name must be 1 to {max} letters, digits, '.', '_' or '-''
  String userNameInvalid({required Object max}) => 'User name must be 1 to ${max} letters, digits, \'.\', \'_\' or \'-\'';

  /// en: 'Invalid email'
  String get emailInvalid => 'Invalid email';

  /// en: 'A user with this user name already exists'
  String get userNameTaken => 'A user with this user name already exists';

  /// en: 'A user with this email already exists'
  String get emailTaken => 'A user with this email already exists';
}

// Path: base.app
class Translations$base$app$en {
  Translations$base$app$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Repolupe logo'
  String get logoAlt => 'Repolupe logo';

  late final Translations$base$app$navigation$en navigation = Translations$base$app$navigation$en.internal(_root);
  late final Translations$base$app$mainContainer$en mainContainer = Translations$base$app$mainContainer$en.internal(_root);
  late final Translations$base$app$genericDeleteDialog$en genericDeleteDialog = Translations$base$app$genericDeleteDialog$en.internal(_root);
}

// Path: base.login
class Translations$base$login$en {
  Translations$base$login$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Login'
  String get login => 'Login';

  /// en: 'Wrong user name or password'
  String get wrongCredentials => 'Wrong user name or password';

  late final Translations$base$login$changePasswordPage$en changePasswordPage = Translations$base$login$changePasswordPage$en.internal(_root);

  /// en: 'Login failed: {error}'
  String loginFailed({required Object error}) => 'Login failed: ${error}';
}

// Path: base.chat
class Translations$base$chat$en {
  Translations$base$chat$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Chats'
  String get title => 'Chats';

  /// en: 'No chats yet'
  String get noChats => 'No chats yet';

  /// en: 'Message'
  String get placeholder => 'Message';

  /// en: 'The selected model is no longer available.'
  String get unknownModel => 'The selected model is no longer available.';

  /// en: 'The attached file is no longer available, please attach it again.'
  String get unknownAttachment => 'The attached file is no longer available, please attach it again.';

  /// en: 'No language model is configured. Ask an admin to add an LLM provider.'
  String get noModelConfigured => 'No language model is configured. Ask an admin to add an LLM provider.';

  /// en: 'Too many answers are being generated. Please wait for one to finish.'
  String get rateLimited => 'Too many answers are being generated. Please wait for one to finish.';

  /// en: 'All Repositories'
  String get allRepositories => 'All Repositories';

  /// en: '(zero) {No repository} (one) {1 repository} (other) {{count} repositories}'
  String repositoryCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    zero: 'No repository',
    one: '1 repository',
    other: '${count} repositories',
  );

  /// en: '(one) {1 move} (other) {{count} moves}'
  String moveCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: '1 move',
    other: '${count} moves',
  );

  /// en: 'Temporary Chat'
  String get temporary => 'Temporary Chat';

  late final Translations$base$chat$startPage$en startPage = Translations$base$chat$startPage$en.internal(_root);
  late final Translations$base$chat$page$en page = Translations$base$chat$page$en.internal(_root);
  late final Translations$base$chat$messageInput$en messageInput = Translations$base$chat$messageInput$en.internal(_root);
  late final Translations$base$chat$assistantMessage$en assistantMessage = Translations$base$chat$assistantMessage$en.internal(_root);
  late final Translations$base$chat$userMessage$en userMessage = Translations$base$chat$userMessage$en.internal(_root);
  late final Translations$base$chat$toolCallList$en toolCallList = Translations$base$chat$toolCallList$en.internal(_root);
  late final Translations$base$chat$toolCallLabel$en toolCallLabel = Translations$base$chat$toolCallLabel$en.internal(_root);
  late final Translations$base$chat$toolCallDialog$en toolCallDialog = Translations$base$chat$toolCallDialog$en.internal(_root);
  late final Translations$base$chat$proposedCommitPanel$en proposedCommitPanel = Translations$base$chat$proposedCommitPanel$en.internal(_root);
  late final Translations$base$chat$renameDialog$en renameDialog = Translations$base$chat$renameDialog$en.internal(_root);
  late final Translations$base$chat$usageDialog$en usageDialog = Translations$base$chat$usageDialog$en.internal(_root);

  /// en: 'Could not load the chats: {error}'
  String loadFailed({required Object error}) => 'Could not load the chats: ${error}';
}

// Path: base.settings
class Translations$base$settings$en {
  Translations$base$settings$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Settings'
  String get title => 'Settings';

  late final Translations$base$settings$page$en page = Translations$base$settings$page$en.internal(_root);
  late final Translations$base$settings$account$en account = Translations$base$settings$account$en.internal(_root);
  late final Translations$base$settings$profile$en profile = Translations$base$settings$profile$en.internal(_root);
  late final Translations$base$settings$preferences$en preferences = Translations$base$settings$preferences$en.internal(_root);
}

// Path: base.repositories
class Translations$base$repositories$en {
  Translations$base$repositories$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Repositories'
  String get title => 'Repositories';

  /// en: 'New Repository'
  String get newRepository => 'New Repository';

  /// en: 'Size'
  String get size => 'Size';

  /// en: 'Share'
  String get share => 'Share';

  /// en: 'Remote'
  String get remote => 'Remote';

  /// en: 'Local'
  String get local => 'Local';

  /// en: 'Remote URL'
  String get remoteUrl => 'Remote URL';

  /// en: 'Branch'
  String get branch => 'Branch';

  /// en: 'Description'
  String get description => 'Description';

  /// en: 'Access token'
  String get accessToken => 'Access token';

  /// en: 'Sync interval'
  String get syncInterval => 'Sync interval';

  /// en: 'Enable write access'
  String get allowCommits => 'Enable write access';

  /// en: 'Description must be at most {max} characters long'
  String descriptionTooLong({required Object max}) => 'Description must be at most ${max} characters long';

  /// en: 'Missing remote URL'
  String get missingRemoteUrl => 'Missing remote URL';

  /// en: 'Missing branch'
  String get missingBranch => 'Missing branch';

  late final Translations$base$repositories$pollInterval$en pollInterval = Translations$base$repositories$pollInterval$en.internal(_root);
  late final Translations$base$repositories$listPage$en listPage = Translations$base$repositories$listPage$en.internal(_root);
  late final Translations$base$repositories$page$en page = Translations$base$repositories$page$en.internal(_root);
  late final Translations$base$repositories$kindDialog$en kindDialog = Translations$base$repositories$kindDialog$en.internal(_root);
  late final Translations$base$repositories$createDialog$en createDialog = Translations$base$repositories$createDialog$en.internal(_root);
  late final Translations$base$repositories$editDialog$en editDialog = Translations$base$repositories$editDialog$en.internal(_root);
  late final Translations$base$repositories$usersCard$en usersCard = Translations$base$repositories$usersCard$en.internal(_root);
  late final Translations$base$repositories$shareDialog$en shareDialog = Translations$base$repositories$shareDialog$en.internal(_root);
}

// Path: base.documents
class Translations$base$documents$en {
  Translations$base$documents$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Documents'
  String get title => 'Documents';

  /// en: 'Documents are converted to text in the background, so the model can read them.'
  String get description => 'Documents are converted to text in the background, so the model can read them.';

  /// en: 'Document'
  String get document => 'Document';

  /// en: 'Details'
  String get detailsColumn => 'Details';

  /// en: 'No documents in this category.'
  String get noData => 'No documents in this category.';

  late final Translations$base$documents$card$en card = Translations$base$documents$card$en.internal(_root);
  late final Translations$base$documents$statusFilter$en statusFilter = Translations$base$documents$statusFilter$en.internal(_root);
  late final Translations$base$documents$details$en details = Translations$base$documents$details$en.internal(_root);

  /// en: 'Could not load the documents: {error}'
  String loadFailed({required Object error}) => 'Could not load the documents: ${error}';
}

// Path: base.admin
class Translations$base$admin$en {
  Translations$base$admin$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$base$admin$users$en users = Translations$base$admin$users$en.internal(_root);
  late final Translations$base$admin$llm$en llm = Translations$base$admin$llm$en.internal(_root);
  late final Translations$base$admin$config$en config = Translations$base$admin$config$en.internal(_root);
  late final Translations$base$admin$extraction$en extraction = Translations$base$admin$extraction$en.internal(_root);
}

// Path: flutter.common
class Translations$flutter$common$en {
  Translations$flutter$common$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$common$unsavedChanges$en unsavedChanges = Translations$flutter$common$unsavedChanges$en.internal(_root);
}

// Path: flutter.setup
class Translations$flutter$setup$en {
  Translations$flutter$setup$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Add account'
  String get addAccount => 'Add account';

  /// en: 'Log in to your Repolupe server, or run Repolupe on this device.'
  String get intro => 'Log in to your Repolupe server, or run Repolupe on this device.';

  /// en: 'Log in to your Repolupe server.'
  String get introRemote => 'Log in to your Repolupe server.';

  /// en: 'Server'
  String get server => 'Server';

  /// en: 'Log in to a Repolupe server, and use its repositories and models.'
  String get remoteDescription => 'Log in to a Repolupe server, and use its repositories and models.';

  /// en: 'Run Repolupe in the app. Chats and repositories stay on this device.'
  String get localDescription => 'Run Repolupe in the app. Chats and repositories stay on this device.';
}

// Path: flutter.account
class Translations$flutter$account$en {
  Translations$flutter$account$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'This device'
  String get thisDevice => 'This device';

  /// en: 'Invalid server address.'
  String get invalidApiUrl => 'Invalid server address.';

  /// en: 'Could not start the local instance: {message}'
  String localStartFailed({required Object message}) => 'Could not start the local instance: ${message}';

  /// en: 'Your session on {server} has ended. Please log in again.'
  String sessionExpired({required Object server}) => 'Your session on ${server} has ended. Please log in again.';
}

// Path: flutter.chat
class Translations$flutter$chat$en {
  Translations$flutter$chat$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$chat$page$en page = Translations$flutter$chat$page$en.internal(_root);
  late final Translations$flutter$chat$markdownContent$en markdownContent = Translations$flutter$chat$markdownContent$en.internal(_root);
  late final Translations$flutter$chat$repositorySheet$en repositorySheet = Translations$flutter$chat$repositorySheet$en.internal(_root);
  late final Translations$flutter$chat$toolCallPage$en toolCallPage = Translations$flutter$chat$toolCallPage$en.internal(_root);
  late final Translations$flutter$chat$presentedFilePage$en presentedFilePage = Translations$flutter$chat$presentedFilePage$en.internal(_root);
  late final Translations$flutter$chat$proposedCommitPage$en proposedCommitPage = Translations$flutter$chat$proposedCommitPage$en.internal(_root);
}

// Path: flutter.settings
class Translations$flutter$settings$en {
  Translations$flutter$settings$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$settings$changePasswordPage$en changePasswordPage = Translations$flutter$settings$changePasswordPage$en.internal(
    _root,
  );
  late final Translations$flutter$settings$accountSheet$en accountSheet = Translations$flutter$settings$accountSheet$en.internal(_root);
  late final Translations$flutter$settings$preferences$en preferences = Translations$flutter$settings$preferences$en.internal(_root);
}

// Path: flutter.validation
class Translations$flutter$validation$en {
  Translations$flutter$validation$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Invalid currency, expected a code like USD or EUR'
  String get invalidCurrency => 'Invalid currency, expected a code like USD or EUR';
}

// Path: flutter.themeMode
class Translations$flutter$themeMode$en {
  Translations$flutter$themeMode$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Theme'
  String get title => 'Theme';

  /// en: 'System'
  String get system => 'System';

  /// en: 'Light'
  String get light => 'Light';

  /// en: 'Dark'
  String get dark => 'Dark';
}

// Path: flutter.repositories
class Translations$flutter$repositories$en {
  Translations$flutter$repositories$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Unknown'
  String get statusUnknown => 'Unknown';

  late final Translations$flutter$repositories$listPage$en listPage = Translations$flutter$repositories$listPage$en.internal(_root);
  late final Translations$flutter$repositories$page$en page = Translations$flutter$repositories$page$en.internal(_root);
  late final Translations$flutter$repositories$form$en form = Translations$flutter$repositories$form$en.internal(_root);
  late final Translations$flutter$repositories$usersCard$en usersCard = Translations$flutter$repositories$usersCard$en.internal(_root);
}

// Path: flutter.documents
class Translations$flutter$documents$en {
  Translations$flutter$documents$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Not synced yet'
  String get notSynced => 'Not synced yet';

  /// en: 'No documents'
  String get noDocuments => 'No documents';

  /// en: 'Show more ({remaining} remaining)'
  String showMore({required Object remaining}) => 'Show more (${remaining} remaining)';

  late final Translations$flutter$documents$details$en details = Translations$flutter$documents$details$en.internal(_root);
}

// Path: flutter.format
class Translations$flutter$format$en {
  Translations$flutter$format$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$format$relative$en relative = Translations$flutter$format$relative$en.internal(_root);
}

// Path: flutter.admin
class Translations$flutter$admin$en {
  Translations$flutter$admin$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$admin$users$en users = Translations$flutter$admin$users$en.internal(_root);
  late final Translations$flutter$admin$llm$en llm = Translations$flutter$admin$llm$en.internal(_root);
  late final Translations$flutter$admin$config$en config = Translations$flutter$admin$config$en.internal(_root);
  late final Translations$flutter$admin$extraction$en extraction = Translations$flutter$admin$extraction$en.internal(_root);
}

// Path: base.app.navigation
class Translations$base$app$navigation$en {
  Translations$base$app$navigation$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Expand'
  String get expand => 'Expand';

  /// en: 'Expand navigation'
  String get expandNavigation => 'Expand navigation';

  /// en: 'Collapse'
  String get collapse => 'Collapse';

  /// en: 'Collapse navigation'
  String get collapseNavigation => 'Collapse navigation';

  /// en: 'New Chat'
  String get newChat => 'New Chat';

  /// en: 'All Chats'
  String get allChats => 'All Chats';
}

// Path: base.app.mainContainer
class Translations$base$app$mainContainer$en {
  Translations$base$app$mainContainer$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '"{title}"'
  String quotedTitle({required Object title}) => '"${title}"';
}

// Path: base.app.genericDeleteDialog
class Translations$base$app$genericDeleteDialog$en {
  Translations$base$app$genericDeleteDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Please verify by entering "{verify}" in the field below:'
  String verifyPrompt({required Object verify}) => 'Please verify by entering "${verify}" in the field below:';

  /// en: 'Verification'
  String get verification => 'Verification';

  /// en: 'Does not match.'
  String get mismatch => 'Does not match.';
}

// Path: base.login.changePasswordPage
class Translations$base$login$changePasswordPage$en {
  Translations$base$login$changePasswordPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Change Password'
  String get title => 'Change Password';

  /// en: 'Change password'
  String get submit => 'Change password';

  /// en: 'Log out'
  String get logout => 'Log out';
}

// Path: base.chat.startPage
class Translations$base$chat$startPage$en {
  Translations$base$chat$startPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'The repositories could not be loaded.'
  String get loadFailed => 'The repositories could not be loaded.';

  /// en: 'No language model is configured yet, so questions cannot be answered.'
  String get noModel => 'No language model is configured yet, so questions cannot be answered.';

  /// en: '{link} to get started.'
  String addProvider({required Object link}) => '${link} to get started.';

  /// en: 'Add an LLM provider'
  String get addProviderLink => 'Add an LLM provider';

  /// en: 'Ask an admin to configure an LLM provider.'
  String get askAdmin => 'Ask an admin to configure an LLM provider.';

  /// en: 'Please wait for the file to be uploaded.'
  String get waitForUpload => 'Please wait for the file to be uploaded.';

  /// en: 'Please enter a question.'
  String get enterQuestion => 'Please enter a question.';

  /// en: 'A selected repository is no longer available.'
  String get unknownRepository => 'A selected repository is no longer available.';
}

// Path: base.chat.page
class Translations$base$chat$page$en {
  Translations$base$chat$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Chat actions'
  String get actions => 'Chat actions';

  /// en: 'Rename'
  String get rename => 'Rename';

  /// en: 'Delete Chat'
  String get deleteTitle => 'Delete Chat';

  /// en: 'Are you sure you want to delete "{title}" with all its messages?'
  String deleteConfirm({required Object title}) => 'Are you sure you want to delete "${title}" with all its messages?';

  /// en: 'Lost connection to the answer. Reload the page to try again.'
  String get connectionLost => 'Lost connection to the answer. Reload the page to try again.';

  /// en: 'Chat not found'
  String get notFound => 'Chat not found';

  /// en: 'Chat renamed.'
  String get renamed => 'Chat renamed.';

  /// en: 'Chat deleted.'
  String get deleted => 'Chat deleted.';

  /// en: 'Could not open the chat: {error}'
  String openFailed({required Object error}) => 'Could not open the chat: ${error}';

  /// en: 'Could not send the message: {error}'
  String sendFailed({required Object error}) => 'Could not send the message: ${error}';

  /// en: 'Could not retry the answer: {error}'
  String retryFailed({required Object error}) => 'Could not retry the answer: ${error}';

  /// en: 'Could not stop the answer: {error}'
  String stopFailed({required Object error}) => 'Could not stop the answer: ${error}';

  /// en: 'Could not rename the chat: {error}'
  String renameFailed({required Object error}) => 'Could not rename the chat: ${error}';

  /// en: 'Could not change the model: {error}'
  String changeModelFailed({required Object error}) => 'Could not change the model: ${error}';

  /// en: 'Could not delete the chat: {error}'
  String deleteFailed({required Object error}) => 'Could not delete the chat: ${error}';
}

// Path: base.chat.messageInput
class Translations$base$chat$messageInput$en {
  Translations$base$chat$messageInput$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Stop'
  String get stop => 'Stop';

  /// en: 'Send'
  String get send => 'Send';

  /// en: 'Drop a file to attach it'
  String get dropHint => 'Drop a file to attach it';

  /// en: 'The file is too large, it may be at most {max}.'
  String fileTooLarge({required Object max}) => 'The file is too large, it may be at most ${max}.';

  /// en: 'Could not upload the file: {error}'
  String uploadFailed({required Object error}) => 'Could not upload the file: ${error}';

  /// en: 'Only one file can be attached to a message.'
  String get oneFileOnly => 'Only one file can be attached to a message.';
}

// Path: base.chat.assistantMessage
class Translations$base$chat$assistantMessage$en {
  Translations$base$chat$assistantMessage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Thinking…'
  String get thinking => 'Thinking…';

  /// en: '(No answer)'
  String get noAnswer => '(No answer)';

  /// en: 'Proposed to store as {path}'
  String proposedStore({required Object path}) => 'Proposed to store as ${path}';

  /// en: 'Proposed change of {path}'
  String proposedChange({required Object path}) => 'Proposed change of ${path}';

  /// en: 'Proposed moves: {moves}'
  String proposedMoves({required Object moves}) => 'Proposed moves: ${moves}';

  /// en: 'The answer could not be generated.'
  String get failed => 'The answer could not be generated.';

  /// en: 'Cancelled'
  String get cancelled => 'Cancelled';

  /// en: 'Show token usage'
  String get showUsage => 'Show token usage';

  /// en: '{seconds}s'
  String durationSeconds({required Object seconds}) => '${seconds}s';

  /// en: '{minutes}m {seconds}s'
  String durationMinutes({required Object minutes, required Object seconds}) => '${minutes}m ${seconds}s';
}

// Path: base.chat.userMessage
class Translations$base$chat$userMessage$en {
  Translations$base$chat$userMessage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Download {name}'
  String download({required Object name}) => 'Download ${name}';
}

// Path: base.chat.toolCallList
class Translations$base$chat$toolCallList$en {
  Translations$base$chat$toolCallList$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Reading the repositories'
  String get running => 'Reading the repositories';

  /// en: '(one) {Used {count} tool} (other) {Used {count} tools}'
  String used({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'Used ${count} tool',
    other: 'Used ${count} tools',
  );

  /// en: '(one) {Used {count} tool ({failed} failed)} (other) {Used {count} tools ({failed} failed)}'
  String usedWithFailed({required num count, required Object failed}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'Used ${count} tool (${failed} failed)',
    other: 'Used ${count} tools (${failed} failed)',
  );
}

// Path: base.chat.toolCallLabel
class Translations$base$chat$toolCallLabel$en {
  Translations$base$chat$toolCallLabel$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '"{pattern}" in {where}'
  String grepPatternIn({required Object pattern, required Object where}) => '"${pattern}" in ${where}';

  /// en: 'in {where}'
  String grepIn({required Object where}) => 'in ${where}';
}

// Path: base.chat.toolCallDialog
class Translations$base$chat$toolCallDialog$en {
  Translations$base$chat$toolCallDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Still running.'
  String get stillRunning => 'Still running.';

  /// en: 'No output.'
  String get noOutput => 'No output.';

  /// en: 'Could not load the tool call: {error}'
  String loadFailed({required Object error}) => 'Could not load the tool call: ${error}';
}

// Path: base.chat.proposedCommitPanel
class Translations$base$chat$proposedCommitPanel$en {
  Translations$base$chat$proposedCommitPanel$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Applied'
  String get applied => 'Applied';

  /// en: 'Applied {relative} ({dateTime})'
  String appliedAt({required Object relative, required Object dateTime}) => 'Applied ${relative} (${dateTime})';

  /// en: 'More'
  String get more => 'More';

  /// en: 'Download as patch file'
  String get downloadPatch => 'Download as patch file';

  /// en: 'This file will be deleted.'
  String get willDelete => 'This file will be deleted.';

  /// en: 'This file will be created.'
  String get willCreate => 'This file will be created.';

  /// en: 'Removed'
  String get removed => 'Removed';

  /// en: 'Unchanged lines'
  String get unchangedLines => 'Unchanged lines';

  /// en: 'removed: {text}'
  String removedLine({required Object text}) => 'removed: ${text}';

  /// en: 'added: {text}'
  String addedLine({required Object text}) => 'added: ${text}';

  /// en: '{from} moved to {to}'
  String movedTo({required Object from, required Object to}) => '${from} moved to ${to}';

  /// en: '(one) {Folder with 1 file} (other) {Folder with {count} files}'
  String folderFiles({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'Folder with 1 file',
    other: 'Folder with ${count} files',
  );

  /// en: 'There is no preview for this kind of file.'
  String get noPreview => 'There is no preview for this kind of file.';

  /// en: 'Only the owner of this repository and the users they gave write access can apply changes.'
  String get cannotCommit => 'Only the owner of this repository and the users they gave write access can apply changes.';

  /// en: 'Enable auto-commit'
  String get enableAutoCommit => 'Enable auto-commit';

  /// en: 'Enable auto-commit?'
  String get autoCommitTitle => 'Enable auto-commit?';

  /// en: 'From now on, changes the assistant proposes are applied as soon as its answer is complete, without asking you. This change is applied now. You can turn this off in your preferences.'
  String get autoCommitText =>
      'From now on, changes the assistant proposes are applied as soon as its answer is complete, without asking you. This change is applied now. You can turn this off in your preferences.';

  /// en: 'Enable and apply'
  String get autoCommitConfirm => 'Enable and apply';

  /// en: 'Apply Change'
  String get apply => 'Apply Change';

  /// en: 'Try Again'
  String get tryAgain => 'Try Again';

  /// en: 'Applied the change to {name}'
  String appliedTo({required Object name}) => 'Applied the change to ${name}';

  /// en: 'Applied the moves'
  String get appliedMoves => 'Applied the moves';

  /// en: 'Could not apply the change: {error}'
  String applyFailed({required Object error}) => 'Could not apply the change: ${error}';

  /// en: 'Could not download the patch: {error}'
  String downloadFailed({required Object error}) => 'Could not download the patch: ${error}';
}

// Path: base.chat.renameDialog
class Translations$base$chat$renameDialog$en {
  Translations$base$chat$renameDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Rename Chat'
  String get title => 'Rename Chat';

  /// en: 'Title'
  String get label => 'Title';

  /// en: 'At most {max} characters.'
  String maxLength({required Object max}) => 'At most ${max} characters.';
}

// Path: base.chat.usageDialog
class Translations$base$chat$usageDialog$en {
  Translations$base$chat$usageDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Token usage'
  String get title => 'Token usage';

  /// en: 'Type'
  String get type => 'Type';

  /// en: 'Tokens'
  String get tokens => 'Tokens';

  /// en: 'Not read from or written to the cache'
  String get inputHint => 'Not read from or written to the cache';

  /// en: 'Cache read'
  String get cacheRead => 'Cache read';

  /// en: 'Input read from the cache'
  String get cacheReadHint => 'Input read from the cache';

  /// en: 'Cache write'
  String get cacheWrite => 'Cache write';

  /// en: 'Input written to the cache'
  String get cacheWriteHint => 'Input written to the cache';

  /// en: 'Including reasoning'
  String get outputHint => 'Including reasoning';

  /// en: 'Total'
  String get total => 'Total';

  /// en: 'Cost'
  String get cost => 'Cost';
}

// Path: base.settings.page
class Translations$base$settings$page$en {
  Translations$base$settings$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Admin'
  String get admin => 'Admin';

  /// en: 'Logout'
  String get logout => 'Logout';

  /// en: 'Add repositories as knowledge base and share them with other users'
  String get repositoriesSubtitle => 'Add repositories as knowledge base and share them with other users';

  /// en: 'Your login details and password'
  String get accountSubtitle => 'Your login details and password';

  /// en: 'What the assistant is told about you'
  String get profileSubtitle => 'What the assistant is told about you';

  /// en: 'Your default model and language'
  String get preferencesSubtitle => 'Your default model and language';

  /// en: 'Create users, set their roles and permissions'
  String get usersSubtitle => 'Create users, set their roles and permissions';

  /// en: 'Configure LLM servers, their models and the default model'
  String get llmSubtitle => 'Configure LLM servers, their models and the default model';

  /// en: 'Follow the conversion of documents to text and retry failed ones'
  String get extractionSubtitle => 'Follow the conversion of documents to text and retry failed ones';

  /// en: 'View the server config and override settings without a restart'
  String get configSubtitle => 'View the server config and override settings without a restart';
}

// Path: base.settings.account
class Translations$base$settings$account$en {
  Translations$base$settings$account$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Account'
  String get title => 'Account';

  late final Translations$base$settings$account$page$en page = Translations$base$settings$account$page$en.internal(_root);
  late final Translations$base$settings$account$changePasswordDialog$en changePasswordDialog =
      Translations$base$settings$account$changePasswordDialog$en.internal(_root);
  late final Translations$base$settings$account$userNameDialog$en userNameDialog = Translations$base$settings$account$userNameDialog$en.internal(
    _root,
  );
  late final Translations$base$settings$account$emailDialog$en emailDialog = Translations$base$settings$account$emailDialog$en.internal(_root);

  /// en: 'You log in with your user name or email.'
  String get loginHint => 'You log in with your user name or email.';
}

// Path: base.settings.profile
class Translations$base$settings$profile$en {
  Translations$base$settings$profile$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Profile'
  String get title => 'Profile';

  /// en: 'Full name'
  String get fullName => 'Full name';

  /// en: 'First name'
  String get firstName => 'First name';

  /// en: 'About'
  String get about => 'About';

  late final Translations$base$settings$profile$page$en page = Translations$base$settings$profile$page$en.internal(_root);
  late final Translations$base$settings$profile$dialog$en dialog = Translations$base$settings$profile$dialog$en.internal(_root);
}

// Path: base.settings.preferences
class Translations$base$settings$preferences$en {
  Translations$base$settings$preferences$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Preferences'
  String get title => 'Preferences';

  /// en: 'Language'
  String get language => 'Language';

  /// en: 'Browser default ({locale})'
  String browserDefault({required Object locale}) => 'Browser default (${locale})';

  /// en: 'Default ({name})'
  String defaultModel({required Object name}) => 'Default (${name})';

  /// en: 'Default (none configured)'
  String get defaultNone => 'Default (none configured)';

  late final Translations$base$settings$preferences$page$en page = Translations$base$settings$preferences$page$en.internal(_root);
  late final Translations$base$settings$preferences$localeDialog$en localeDialog = Translations$base$settings$preferences$localeDialog$en.internal(
    _root,
  );
  late final Translations$base$settings$preferences$modelDialog$en modelDialog = Translations$base$settings$preferences$modelDialog$en.internal(
    _root,
  );
}

// Path: base.repositories.pollInterval
class Translations$base$repositories$pollInterval$en {
  Translations$base$repositories$pollInterval$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Every minute'
  String get minute => 'Every minute';

  /// en: 'Every 5 minutes'
  String get minutes5 => 'Every 5 minutes';

  /// en: 'Every 15 minutes'
  String get minutes15 => 'Every 15 minutes';

  /// en: 'Every hour'
  String get hour => 'Every hour';

  /// en: 'Every 6 hours'
  String get hours6 => 'Every 6 hours';

  /// en: 'Daily'
  String get daily => 'Daily';

  /// en: 'Every {seconds} seconds'
  String seconds({required Object seconds}) => 'Every ${seconds} seconds';
}

// Path: base.repositories.listPage
class Translations$base$repositories$listPage$en {
  Translations$base$repositories$listPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(zero) {{count} Repositories} (one) {{count} Repository} (other) {{count} Repositories}'
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    zero: '${count} Repositories',
    one: '${count} Repository',
    other: '${count} Repositories',
  );

  /// en: 'Your repositories and those shared with you. In chats, the model reads their files to answer your questions.'
  String get description => 'Your repositories and those shared with you. In chats, the model reads their files to answer your questions.';

  /// en: 'No repositories yet'
  String get emptyTitle => 'No repositories yet';

  /// en: 'A repository is a git branch that Repolupe mirrors and keeps in sync. Once it is synced, you can ask questions about it in chats, and the model reads its files to answer them.'
  String get emptyText =>
      'A repository is a git branch that Repolupe mirrors and keeps in sync. Once it is synced, you can ask questions about it in chats, and the model reads its files to answer them.';

  /// en: 'No repositories match your search.'
  String get noMatch => 'No repositories match your search.';

  /// en: 'Repository added, syncing…'
  String get added => 'Repository added, syncing…';

  /// en: 'Could not load the repositories: {error}'
  String loadFailed({required Object error}) => 'Could not load the repositories: ${error}';

  /// en: 'Could not add the repository: {error}'
  String createFailed({required Object error}) => 'Could not add the repository: ${error}';
}

// Path: base.repositories.page
class Translations$base$repositories$page$en {
  Translations$base$repositories$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Here you can update the repository details, trigger sync jobs and share the repository with other users.'
  String get ownerIntro => 'Here you can update the repository details, trigger sync jobs and share the repository with other users.';

  /// en: 'Here you can update the repository details and share the repository with other users.'
  String get ownerIntroLocal => 'Here you can update the repository details and share the repository with other users.';

  /// en: 'This repository is shared with you. Here you can see its details and sync status.'
  String get sharedIntro => 'This repository is shared with you. Here you can see its details and sync status.';

  /// en: 'Owner'
  String get owner => 'Owner';

  /// en: 'You'
  String get ownerYou => 'You';

  /// en: 'Shared with you'
  String get ownerShared => 'Shared with you';

  /// en: 'Git {git}, LFS {lfs}'
  String sizeSplit({required Object git, required Object lfs}) => 'Git ${git}, LFS ${lfs}';

  /// en: 'Only the branch {branch} is fetched, so the remote may be larger'
  String sizeTitle({required Object branch}) => 'Only the branch ${branch} is fetched, so the remote may be larger';

  /// en: 'Created'
  String get created => 'Created';

  /// en: 'Ask a question'
  String get askQuestion => 'Ask a question';

  /// en: 'Last sync failed'
  String get lastSyncFailed => 'Last sync failed';

  /// en: 'None (local repository on this server)'
  String get remoteNone => 'None (local repository on this server)';

  /// en: 'None (public)'
  String get tokenNone => 'None (public)';

  /// en: 'Set'
  String get tokenSet => 'Set';

  /// en: 'Write access'
  String get writeAccess => 'Write access';

  /// en: 'Enabled (the model can propose changes)'
  String get writeAccessEnabled => 'Enabled (the model can propose changes)';

  /// en: 'Disabled (the model can only read files)'
  String get writeAccessDisabled => 'Disabled (the model can only read files)';

  /// en: 'Leave'
  String get leave => 'Leave';

  /// en: 'Sync'
  String get sync => 'Sync';

  /// en: 'Interval'
  String get interval => 'Interval';

  /// en: 'After each commit'
  String get intervalLocal => 'After each commit';

  /// en: 'Current version'
  String get headCommit => 'Current version';

  /// en: 'Last synced'
  String get lastSynced => 'Last synced';

  /// en: 'Sync started'
  String get syncStarted => 'Sync started';

  /// en: 'Next sync'
  String get nextSync => 'Next sync';

  /// en: 'Sync now'
  String get syncNow => 'Sync now';

  /// en: 'Delete Repository'
  String get deleteTitle => 'Delete Repository';

  /// en: 'Only the copy of the repository on this server is deleted. The remote repository is not affected. Chats and users it is shared with lose access to it.'
  String get deleteText =>
      'Only the copy of the repository on this server is deleted. The remote repository is not affected. Chats and users it is shared with lose access to it.';

  /// en: 'The repository only exists on this server, so its files and history are deleted for good. Chats and users it is shared with lose access to it.'
  String get deleteTextLocal =>
      'The repository only exists on this server, so its files and history are deleted for good. Chats and users it is shared with lose access to it.';

  /// en: 'Leave Repository'
  String get leaveTitle => 'Leave Repository';

  /// en: 'You lose access to this repository, and it is removed from your chats. The owner can share it with you again.'
  String get leaveText => 'You lose access to this repository, and it is removed from your chats. The owner can share it with you again.';

  /// en: 'Repository not found'
  String get notFound => 'Repository not found';

  /// en: 'Sync requested.'
  String get syncRequested => 'Sync requested.';

  /// en: 'Repository updated.'
  String get updated => 'Repository updated.';

  /// en: 'Repository deleted.'
  String get deleted => 'Repository deleted.';

  /// en: 'You left the repository.'
  String get left => 'You left the repository.';

  /// en: 'Could not load the repository: {error}'
  String loadFailed({required Object error}) => 'Could not load the repository: ${error}';

  /// en: 'Could not request the sync: {error}'
  String syncFailed({required Object error}) => 'Could not request the sync: ${error}';

  /// en: 'Could not save the repository: {error}'
  String saveFailed({required Object error}) => 'Could not save the repository: ${error}';

  /// en: 'Could not delete the repository: {error}'
  String deleteFailed({required Object error}) => 'Could not delete the repository: ${error}';

  /// en: 'Could not leave the repository: {error}'
  String leaveFailed({required Object error}) => 'Could not leave the repository: ${error}';
}

// Path: base.repositories.kindDialog
class Translations$base$repositories$kindDialog$en {
  Translations$base$repositories$kindDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Mirror a branch of a git repository, e.g. on GitHub, GitLab or Forgejo, and keep it in sync.'
  String get remoteDescription => 'Mirror a branch of a git repository, e.g. on GitHub, GitLab or Forgejo, and keep it in sync.';

  /// en: 'Start an empty repository that only exists on this server.'
  String get localDescription => 'Start an empty repository that only exists on this server.';
}

// Path: base.repositories.createDialog
class Translations$base$repositories$createDialog$en {
  Translations$base$repositories$createDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'New Remote Repository'
  String get titleRemote => 'New Remote Repository';

  /// en: 'New Local Repository'
  String get titleLocal => 'New Local Repository';

  /// en: 'Description (optional)'
  String get descriptionOptional => 'Description (optional)';

  /// en: 'Helps the model decide when to look into this repository.'
  String get descriptionHint => 'Helps the model decide when to look into this repository.';

  /// en: 'Access token (optional)'
  String get tokenOptional => 'Access token (optional)';

  /// en: 'Needed for private repositories.'
  String get tokenHint => 'Needed for private repositories.';

  /// en: 'Without write access, the model cannot add files, so the repository stays empty.'
  String get allowCommitsHintLocal => 'Without write access, the model cannot add files, so the repository stays empty.';

  /// en: 'As an admin, you may also use http:// and internal hosts.'
  String get remoteUrlHintAdmin => 'As an admin, you may also use http:// and internal hosts.';

  /// en: 'Must use https:// and a host that resolves to a public address.'
  String get remoteUrlHintUser => 'Must use https:// and a host that resolves to a public address.';

  /// en: 'Checking the remote, this can take a few seconds…'
  String get checkingRemote => 'Checking the remote, this can take a few seconds…';
}

// Path: base.repositories.editDialog
class Translations$base$repositories$editDialog$en {
  Translations$base$repositories$editDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Edit Repository'
  String get title => 'Edit Repository';

  /// en: 'Keep current token'
  String get keepToken => 'Keep current token';

  /// en: 'Keep current token (•••• {hint})'
  String keepTokenWithHint({required Object hint}) => 'Keep current token (•••• ${hint})';

  /// en: 'Remove token (public repository)'
  String get removeToken => 'Remove token (public repository)';

  /// en: 'No token (public repository)'
  String get noToken => 'No token (public repository)';

  /// en: 'Set new token'
  String get setToken => 'Set new token';

  /// en: 'New access token'
  String get newToken => 'New access token';

  /// en: 'A token with read access, e.g. a personal access token.'
  String get newTokenHint => 'A token with read access, e.g. a personal access token.';

  /// en: 'The remote moved to another host, so the current token cannot be kept. Set a new token, or remove it if the new remote is public.'
  String get hostChanged =>
      'The remote moved to another host, so the current token cannot be kept. Set a new token, or remove it if the new remote is public.';

  /// en: 'Missing token'
  String get missingToken => 'Missing token';
}

// Path: base.repositories.usersCard
class Translations$base$repositories$usersCard$en {
  Translations$base$repositories$usersCard$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Sharing'
  String get title => 'Sharing';

  /// en: 'Users it is shared with can read this repository and use it in their chats, but cannot change, sync or delete it. If write access is enabled, you can let them apply the changes the model proposes, using this repository's access token.'
  String get description =>
      'Users it is shared with can read this repository and use it in their chats, but cannot change, sync or delete it. If write access is enabled, you can let them apply the changes the model proposes, using this repository\'s access token.';

  /// en: 'Users it is shared with can read this repository and use it in their chats, but cannot change or delete it. If write access is enabled, you can let them apply the changes the model proposes.'
  String get descriptionLocal =>
      'Users it is shared with can read this repository and use it in their chats, but cannot change or delete it. If write access is enabled, you can let them apply the changes the model proposes.';

  /// en: 'Not shared with anyone'
  String get notShared => 'Not shared with anyone';

  /// en: 'User'
  String get user => 'User';

  /// en: 'Shared'
  String get sharedAt => 'Shared';

  /// en: 'Write access'
  String get canCommit => 'Write access';

  /// en: 'Enable write access for the repository first'
  String get canCommitOff => 'Enable write access for the repository first';

  /// en: 'Stop sharing'
  String get stopSharing => 'Stop sharing';

  /// en: 'Stop Sharing'
  String get stopSharingTitle => 'Stop Sharing';

  /// en: '{name} will lose access to this repository, and it is removed from their chats.'
  String stopSharingText({required Object name}) => '${name} will lose access to this repository, and it is removed from their chats.';

  /// en: 'Repository shared.'
  String get shared => 'Repository shared.';

  /// en: 'No user with this user name or email'
  String get unknownUser => 'No user with this user name or email';

  /// en: 'Stopped sharing.'
  String get stopped => 'Stopped sharing.';

  /// en: 'Could not load the users: {error}'
  String loadFailed({required Object error}) => 'Could not load the users: ${error}';

  /// en: 'Could not share the repository: {error}'
  String shareFailed({required Object error}) => 'Could not share the repository: ${error}';

  /// en: 'Could not change the write access: {error}'
  String canCommitFailed({required Object error}) => 'Could not change the write access: ${error}';

  /// en: 'Could not stop sharing: {error}'
  String stopFailed({required Object error}) => 'Could not stop sharing: ${error}';
}

// Path: base.repositories.shareDialog
class Translations$base$repositories$shareDialog$en {
  Translations$base$repositories$shareDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Share Repository'
  String get title => 'Share Repository';

  /// en: 'The user can read this repository and use it in their chats, but cannot change, sync or delete it.'
  String get description => 'The user can read this repository and use it in their chats, but cannot change, sync or delete it.';

  /// en: 'Missing user name or email'
  String get missing => 'Missing user name or email';
}

// Path: base.documents.card
class Translations$base$documents$card$en {
  Translations$base$documents$card$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'The OCR service is unavailable. Conversions are paused until {time}.'
  String paused({required Object time}) => 'The OCR service is unavailable. Conversions are paused until ${time}.';
}

// Path: base.documents.statusFilter
class Translations$base$documents$statusFilter$en {
  Translations$base$documents$statusFilter$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Filter by status'
  String get filterByStatus => 'Filter by status';

  /// en: 'All'
  String get all => 'All';
}

// Path: base.documents.details
class Translations$base$documents$details$en {
  Translations$base$documents$details$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Started {relative}'
  String started({required Object relative}) => 'Started ${relative}';

  /// en: '{reason} Tried again {relative}.'
  String skipped({required Object reason, required Object relative}) => '${reason} Tried again ${relative}.';

  /// en: 'The file is stored with Git LFS and could not be downloaded.'
  String get lfsObjectMissing => 'The file is stored with Git LFS and could not be downloaded.';

  /// en: 'The file could not be read.'
  String get unreadable => 'The file could not be read.';

  /// en: 'Settings change'
  String get settingsChanged => 'Settings change';

  /// en: 'New'
  String get kNew => 'New';
}

// Path: base.admin.users
class Translations$base$admin$users$en {
  Translations$base$admin$users$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Users'
  String get title => 'Users';

  /// en: 'Must change password'
  String get mustChangePassword => 'Must change password';

  /// en: 'They choose their own password after logging in with this one'
  String get chooseOwnPasswordHint => 'They choose their own password after logging in with this one';

  late final Translations$base$admin$users$page$en page = Translations$base$admin$users$page$en.internal(_root);
  late final Translations$base$admin$users$createDialog$en createDialog = Translations$base$admin$users$createDialog$en.internal(_root);
  late final Translations$base$admin$users$editDialog$en editDialog = Translations$base$admin$users$editDialog$en.internal(_root);
  late final Translations$base$admin$users$passwordDialog$en passwordDialog = Translations$base$admin$users$passwordDialog$en.internal(_root);
  late final Translations$base$admin$users$deleteDialog$en deleteDialog = Translations$base$admin$users$deleteDialog$en.internal(_root);
}

// Path: base.admin.llm
class Translations$base$admin$llm$en {
  Translations$base$admin$llm$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'LLM Providers'
  String get title => 'LLM Providers';

  /// en: 'New Provider'
  String get newProvider => 'New Provider';

  /// en: 'Price per 1M tokens'
  String get pricePerMillion => 'Price per 1M tokens';

  late final Translations$base$admin$llm$page$en page = Translations$base$admin$llm$page$en.internal(_root);
  late final Translations$base$admin$llm$providerDialog$en providerDialog = Translations$base$admin$llm$providerDialog$en.internal(_root);
  late final Translations$base$admin$llm$modelDialog$en modelDialog = Translations$base$admin$llm$modelDialog$en.internal(_root);
  late final Translations$base$admin$llm$remoteModelsDialog$en remoteModelsDialog = Translations$base$admin$llm$remoteModelsDialog$en.internal(_root);
}

// Path: base.admin.config
class Translations$base$admin$config$en {
  Translations$base$admin$config$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Config'
  String get title => 'Config';

  /// en: 'Override'
  String get overrideAction => 'Override';

  late final Translations$base$admin$config$page$en page = Translations$base$admin$config$page$en.internal(_root);
  late final Translations$base$admin$config$overrideDialog$en overrideDialog = Translations$base$admin$config$overrideDialog$en.internal(_root);
}

// Path: base.admin.extraction
class Translations$base$admin$extraction$en {
  Translations$base$admin$extraction$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Document Extraction'
  String get title => 'Document Extraction';

  late final Translations$base$admin$extraction$page$en page = Translations$base$admin$extraction$page$en.internal(_root);
}

// Path: flutter.common.unsavedChanges
class Translations$flutter$common$unsavedChanges$en {
  Translations$flutter$common$unsavedChanges$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Discard changes?'
  String get title => 'Discard changes?';

  /// en: 'Your changes have not been saved.'
  String get text => 'Your changes have not been saved.';

  /// en: 'Keep editing'
  String get keepEditing => 'Keep editing';

  /// en: 'Discard'
  String get discard => 'Discard';
}

// Path: flutter.chat.page
class Translations$flutter$chat$page$en {
  Translations$flutter$chat$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Turn off temporary chat'
  String get temporaryOff => 'Turn off temporary chat';
}

// Path: flutter.chat.markdownContent
class Translations$flutter$chat$markdownContent$en {
  Translations$flutter$chat$markdownContent$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Could not open {link}'
  String openLinkFailed({required Object link}) => 'Could not open ${link}';
}

// Path: flutter.chat.repositorySheet
class Translations$flutter$chat$repositorySheet$en {
  Translations$flutter$chat$repositorySheet$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'A chat keeps the repositories it was started with.'
  String get fixedHint => 'A chat keeps the repositories it was started with.';

  /// en: 'Unavailable repository'
  String get unavailable => 'Unavailable repository';
}

// Path: flutter.chat.toolCallPage
class Translations$flutter$chat$toolCallPage$en {
  Translations$flutter$chat$toolCallPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Commit {sha}'
  String commit({required Object sha}) => 'Commit ${sha}';
}

// Path: flutter.chat.presentedFilePage
class Translations$flutter$chat$presentedFilePage$en {
  Translations$flutter$chat$presentedFilePage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'This file cannot be shown in the app.'
  String get cannotShow => 'This file cannot be shown in the app.';
}

// Path: flutter.chat.proposedCommitPage
class Translations$flutter$chat$proposedCommitPage$en {
  Translations$flutter$chat$proposedCommitPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Not applied yet.'
  String get notApplied => 'Not applied yet.';
}

// Path: flutter.settings.changePasswordPage
class Translations$flutter$settings$changePasswordPage$en {
  Translations$flutter$settings$changePasswordPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'You must change your password before you can continue.'
  String get intro => 'You must change your password before you can continue.';
}

// Path: flutter.settings.accountSheet
class Translations$flutter$settings$accountSheet$en {
  Translations$flutter$settings$accountSheet$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Accounts'
  String get accounts => 'Accounts';

  /// en: 'Add account'
  String get addAccount => 'Add account';
}

// Path: flutter.settings.preferences
class Translations$flutter$settings$preferences$en {
  Translations$flutter$settings$preferences$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Device default'
  String get deviceDefault => 'Device default';

  /// en: 'Device default ({locale})'
  String deviceDefaultWithLocale({required Object locale}) => 'Device default (${locale})';

  late final Translations$flutter$settings$preferences$modelSheet$en modelSheet = Translations$flutter$settings$preferences$modelSheet$en.internal(
    _root,
  );
}

// Path: flutter.repositories.listPage
class Translations$flutter$repositories$listPage$en {
  Translations$flutter$repositories$listPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Repository added.'
  String get addedLocal => 'Repository added.';
}

// Path: flutter.repositories.page
class Translations$flutter$repositories$page$en {
  Translations$flutter$repositories$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Set (•••• {hint})'
  String tokenSetWithHint({required Object hint}) => 'Set (•••• ${hint})';
}

// Path: flutter.repositories.form
class Translations$flutter$repositories$form$en {
  Translations$flutter$repositories$form$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Show token'
  String get showToken => 'Show token';

  /// en: 'Hide token'
  String get hideToken => 'Hide token';
}

// Path: flutter.repositories.usersCard
class Translations$flutter$repositories$usersCard$en {
  Translations$flutter$repositories$usersCard$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Shared {relative}'
  String sharedRelative({required Object relative}) => 'Shared ${relative}';

  /// en: 'Applies the changes the model proposes to them'
  String get canCommitOn => 'Applies the changes the model proposes to them';
}

// Path: flutter.documents.details
class Translations$flutter$documents$details$en {
  Translations$flutter$documents$details$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Path'
  String get path => 'Path';

  /// en: 'Started'
  String get started => 'Started';

  /// en: 'Reason'
  String get reason => 'Reason';

  /// en: 'Tried again'
  String get triedAgain => 'Tried again';

  /// en: 'Settings change: the document is converted again with the current settings.'
  String get settingsChanged => 'Settings change: the document is converted again with the current settings.';

  /// en: 'New: the document has not been converted yet.'
  String get newDocument => 'New: the document has not been converted yet.';

  /// en: 'Converted (earlier settings)'
  String get convertedEarlier => 'Converted (earlier settings)';

  /// en: 'Failed {relative}'
  String failedRelative({required Object relative}) => 'Failed ${relative}';

  /// en: 'Pages were recognized with OCR, so the text may contain errors.'
  String get ocrUsed => 'Pages were recognized with OCR, so the text may contain errors.';

  /// en: 'No'
  String get ocrNotUsed => 'No';
}

// Path: flutter.format.relative
class Translations$flutter$format$relative$en {
  Translations$flutter$format$relative$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'just now'
  String get justNow => 'just now';

  /// en: '(one) {1 minute ago} (other) {{count} minutes ago}'
  String minutesAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: '1 minute ago',
    other: '${count} minutes ago',
  );

  /// en: '(one) {in 1 minute} (other) {in {count} minutes}'
  String inMinutes({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'in 1 minute',
    other: 'in ${count} minutes',
  );

  /// en: '(one) {1 hour ago} (other) {{count} hours ago}'
  String hoursAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: '1 hour ago',
    other: '${count} hours ago',
  );

  /// en: '(one) {in 1 hour} (other) {in {count} hours}'
  String inHours({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'in 1 hour',
    other: 'in ${count} hours',
  );

  /// en: '(one) {1 day ago} (other) {{count} days ago}'
  String daysAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: '1 day ago',
    other: '${count} days ago',
  );

  /// en: '(one) {in 1 day} (other) {in {count} days}'
  String inDays({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'in 1 day',
    other: 'in ${count} days',
  );
}

// Path: flutter.admin.users
class Translations$flutter$admin$users$en {
  Translations$flutter$admin$users$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Show password'
  String get showPassword => 'Show password';

  /// en: 'Hide password'
  String get hidePassword => 'Hide password';

  late final Translations$flutter$admin$users$page$en page = Translations$flutter$admin$users$page$en.internal(_root);
  late final Translations$flutter$admin$users$userPage$en userPage = Translations$flutter$admin$users$userPage$en.internal(_root);
  late final Translations$flutter$admin$users$form$en form = Translations$flutter$admin$users$form$en.internal(_root);
  late final Translations$flutter$admin$users$flags$en flags = Translations$flutter$admin$users$flags$en.internal(_root);
}

// Path: flutter.admin.llm
class Translations$flutter$admin$llm$en {
  Translations$flutter$admin$llm$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$admin$llm$page$en page = Translations$flutter$admin$llm$page$en.internal(_root);
  late final Translations$flutter$admin$llm$namePicker$en namePicker = Translations$flutter$admin$llm$namePicker$en.internal(_root);
  late final Translations$flutter$admin$llm$providerForm$en providerForm = Translations$flutter$admin$llm$providerForm$en.internal(_root);
  late final Translations$flutter$admin$llm$modelForm$en modelForm = Translations$flutter$admin$llm$modelForm$en.internal(_root);
}

// Path: flutter.admin.config
class Translations$flutter$admin$config$en {
  Translations$flutter$admin$config$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$admin$config$page$en page = Translations$flutter$admin$config$page$en.internal(_root);
  late final Translations$flutter$admin$config$overrideDialog$en overrideDialog = Translations$flutter$admin$config$overrideDialog$en.internal(_root);
  late final Translations$flutter$admin$config$mistralKeySheet$en mistralKeySheet = Translations$flutter$admin$config$mistralKeySheet$en.internal(
    _root,
  );
}

// Path: flutter.admin.extraction
class Translations$flutter$admin$extraction$en {
  Translations$flutter$admin$extraction$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$flutter$admin$extraction$page$en page = Translations$flutter$admin$extraction$page$en.internal(_root);
}

// Path: base.settings.account.page
class Translations$base$settings$account$page$en {
  Translations$base$settings$account$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Member since'
  String get memberSince => 'Member since';

  /// en: 'User name saved'
  String get userNameSaved => 'User name saved';

  /// en: 'Email saved'
  String get emailSaved => 'Email saved';

  /// en: 'Password changed. Your other sessions were signed out.'
  String get passwordChanged => 'Password changed. Your other sessions were signed out.';

  /// en: 'Could not save the user name: {error}'
  String userNameSaveFailed({required Object error}) => 'Could not save the user name: ${error}';

  /// en: 'Could not save the email: {error}'
  String emailSaveFailed({required Object error}) => 'Could not save the email: ${error}';

  /// en: 'Could not change the password: {error}'
  String changePasswordFailed({required Object error}) => 'Could not change the password: ${error}';
}

// Path: base.settings.account.changePasswordDialog
class Translations$base$settings$account$changePasswordDialog$en {
  Translations$base$settings$account$changePasswordDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Change Password'
  String get title => 'Change Password';

  /// en: 'All your other sessions will be signed out.'
  String get signOutNote => 'All your other sessions will be signed out.';

  /// en: 'Please fill in all fields.'
  String get fillAll => 'Please fill in all fields.';
}

// Path: base.settings.account.userNameDialog
class Translations$base$settings$account$userNameDialog$en {
  Translations$base$settings$account$userNameDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Change User Name'
  String get title => 'Change User Name';
}

// Path: base.settings.account.emailDialog
class Translations$base$settings$account$emailDialog$en {
  Translations$base$settings$account$emailDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Change Email'
  String get title => 'Change Email';
}

// Path: base.settings.profile.page
class Translations$base$settings$profile$page$en {
  Translations$base$settings$profile$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'What the assistant is told about you, so it knows who "I" is in your questions.'
  String get description => 'What the assistant is told about you, so it knows who "I" is in your questions.';

  /// en: 'Profile updated.'
  String get updated => 'Profile updated.';

  /// en: 'Could not save the profile: {error}'
  String saveFailed({required Object error}) => 'Could not save the profile: ${error}';
}

// Path: base.settings.profile.dialog
class Translations$base$settings$profile$dialog$en {
  Translations$base$settings$profile$dialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Edit Profile'
  String get title => 'Edit Profile';

  /// en: 'This is what the assistant is told about you, so it knows who "I" is in your questions.'
  String get description => 'This is what the assistant is told about you, so it knows who "I" is in your questions.';

  /// en: 'As it appears in documents'
  String get fullNameHint => 'As it appears in documents';

  /// en: 'E.g. your role, the projects you work on, or how you like answers.'
  String get aboutPlaceholder => 'E.g. your role, the projects you work on, or how you like answers.';

  /// en: 'Full name must be at most {max} characters long.'
  String fullNameTooLong({required Object max}) => 'Full name must be at most ${max} characters long.';

  /// en: 'First name must be at most {max} characters long.'
  String firstNameTooLong({required Object max}) => 'First name must be at most ${max} characters long.';

  /// en: 'About must be at most {max} characters long.'
  String aboutTooLong({required Object max}) => 'About must be at most ${max} characters long.';
}

// Path: base.settings.preferences.page
class Translations$base$settings$preferences$page$en {
  Translations$base$settings$preferences$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'No models configured'
  String get noModels => 'No models configured';

  /// en: 'No models configured. Ask an admin to add one.'
  String get noModelsAskAdmin => 'No models configured. Ask an admin to add one.';

  /// en: 'Model updated.'
  String get modelUpdated => 'Model updated.';

  /// en: 'Language updated.'
  String get languageUpdated => 'Language updated.';

  /// en: 'Apply changes automatically'
  String get autoCommit => 'Apply changes automatically';

  /// en: 'Changes the assistant proposes are applied as soon as its answer is complete.'
  String get autoCommitHint => 'Changes the assistant proposes are applied as soon as its answer is complete.';

  /// en: 'Proposed changes are now applied automatically.'
  String get autoCommitOn => 'Proposed changes are now applied automatically.';

  /// en: 'Proposed changes now wait for you to apply them.'
  String get autoCommitOff => 'Proposed changes now wait for you to apply them.';

  /// en: 'Could not load the models: {error}'
  String modelsLoadFailed({required Object error}) => 'Could not load the models: ${error}';

  /// en: 'Could not save the model: {error}'
  String modelSaveFailed({required Object error}) => 'Could not save the model: ${error}';

  /// en: 'Could not save the language: {error}'
  String languageSaveFailed({required Object error}) => 'Could not save the language: ${error}';

  /// en: 'Could not save the setting: {error}'
  String autoCommitSaveFailed({required Object error}) => 'Could not save the setting: ${error}';
}

// Path: base.settings.preferences.localeDialog
class Translations$base$settings$preferences$localeDialog$en {
  Translations$base$settings$preferences$localeDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Edit Language'
  String get title => 'Edit Language';

  /// en: 'The language the model answers in, and also the language of the interface if it is available in it.'
  String get description => 'The language the model answers in, and also the language of the interface if it is available in it.';

  /// en: 'Language (BCP 47)'
  String get label => 'Language (BCP 47)';
}

// Path: base.settings.preferences.modelDialog
class Translations$base$settings$preferences$modelDialog$en {
  Translations$base$settings$preferences$modelDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Edit Model'
  String get title => 'Edit Model';

  /// en: 'The model that answers your questions.'
  String get description => 'The model that answers your questions.';
}

// Path: base.admin.users.page
class Translations$base$admin$users$page$en {
  Translations$base$admin$users$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(zero) {{count} Users} (one) {{count} User} (other) {{count} Users}'
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    zero: '${count} Users',
    one: '${count} User',
    other: '${count} Users',
  );

  /// en: 'Every user has their own chats and, if allowed, their own repositories. LLM providers and models are set up by admins and used by everyone.'
  String get description =>
      'Every user has their own chats and, if allowed, their own repositories. LLM providers and models are set up by admins and used by everyone.';

  /// en: 'New User'
  String get newUser => 'New User';

  /// en: 'User'
  String get user => 'User';

  /// en: 'Identity'
  String get identity => 'Identity';

  /// en: 'No users'
  String get noUsers => 'No users';

  /// en: 'Login disabled'
  String get loginDisabled => 'Login disabled';

  /// en: 'Password change required'
  String get passwordChangeRequired => 'Password change required';

  /// en: 'Manage'
  String get manage => 'Manage';

  /// en: 'Read only'
  String get readOnly => 'Read only';

  /// en: 'Editable'
  String get editable => 'Editable';

  /// en: 'Fixed'
  String get fixed => 'Fixed';

  /// en: 'You cannot delete yourself'
  String get cannotDeleteSelf => 'You cannot delete yourself';

  /// en: 'Admins cannot be deleted'
  String get cannotDeleteAdmin => 'Admins cannot be deleted';

  /// en: 'Set password'
  String get setPassword => 'Set password';

  /// en: 'Change your own password in your account settings'
  String get cannotSetOwnPassword => 'Change your own password in your account settings';

  /// en: 'User created.'
  String get created => 'User created.';

  /// en: 'User updated.'
  String get updated => 'User updated.';

  /// en: 'Password set.'
  String get passwordSet => 'Password set.';

  /// en: 'User deleted.'
  String get deleted => 'User deleted.';

  /// en: 'Could not load the users: {error}'
  String loadFailed({required Object error}) => 'Could not load the users: ${error}';

  /// en: 'Could not create the user: {error}'
  String createFailed({required Object error}) => 'Could not create the user: ${error}';

  /// en: 'Could not save the user: {error}'
  String saveFailed({required Object error}) => 'Could not save the user: ${error}';

  /// en: 'Could not set the password: {error}'
  String setPasswordFailed({required Object error}) => 'Could not set the password: ${error}';

  /// en: 'Could not delete the user: {error}'
  String deleteFailed({required Object error}) => 'Could not delete the user: ${error}';
}

// Path: base.admin.users.createDialog
class Translations$base$admin$users$createDialog$en {
  Translations$base$admin$users$createDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Create User'
  String get title => 'Create User';
}

// Path: base.admin.users.editDialog
class Translations$base$admin$users$editDialog$en {
  Translations$base$admin$users$editDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Edit User'
  String get title => 'Edit User';

  /// en: 'Admins cannot be restricted'
  String get adminUnrestricted => 'Admins cannot be restricted';

  /// en: 'Can log in'
  String get canLogin => 'Can log in';

  /// en: 'Turning this off signs the user out everywhere'
  String get canLoginHint => 'Turning this off signs the user out everywhere';

  /// en: 'Can manage repositories'
  String get canManageRepositories => 'Can manage repositories';

  /// en: 'Without it, the Repositories page is hidden and they can only ask about repositories shared with them'
  String get canManageRepositoriesHint => 'Without it, the Repositories page is hidden and they can only ask about repositories shared with them';

  /// en: 'Can change user name and email'
  String get canChangeIdentity => 'Can change user name and email';

  /// en: 'Without it, only admins can change them'
  String get canChangeIdentityHint => 'Without it, only admins can change them';

  /// en: 'Until then, the user can do nothing else after logging in'
  String get mustChangePasswordHint => 'Until then, the user can do nothing else after logging in';
}

// Path: base.admin.users.passwordDialog
class Translations$base$admin$users$passwordDialog$en {
  Translations$base$admin$users$passwordDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Set Password'
  String get title => 'Set Password';

  /// en: 'Sets a new password for {name} and signs them out everywhere.'
  String intro({required Object name}) => 'Sets a new password for ${name} and signs them out everywhere.';
}

// Path: base.admin.users.deleteDialog
class Translations$base$admin$users$deleteDialog$en {
  Translations$base$admin$users$deleteDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Delete User'
  String get title => 'Delete User';

  /// en: 'This user will be deleted:'
  String get intro => 'This user will be deleted:';

  /// en: 'Their sessions, chats and repositories are deleted too. Repositories they own are also removed for everyone they were shared with.'
  String get consequences =>
      'Their sessions, chats and repositories are deleted too. Repositories they own are also removed for everyone they were shared with.';
}

// Path: base.admin.llm.page
class Translations$base$admin$llm$page$en {
  Translations$base$admin$llm$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(zero) {{count} Models} (one) {{count} Model} (other) {{count} Models}'
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    zero: '${count} Models',
    one: '${count} Model',
    other: '${count} Models',
  );

  /// en: 'A provider is an LLM server: the Anthropic API, or any OpenAI-compatible server such as OpenRouter, Ollama, vLLM or LM Studio.'
  String get providerIntro =>
      'A provider is an LLM server: the Anthropic API, or any OpenAI-compatible server such as OpenRouter, Ollama, vLLM or LM Studio.';

  /// en: 'Models belong to a provider and must support streaming and tool calling.'
  String get modelsIntro => 'Models belong to a provider and must support streaming and tool calling.';

  /// en: 'The default model ({icon}) answers for users who did not choose one in their settings.'
  String defaultIntro({required Object icon}) => 'The default model (${icon}) answers for users who did not choose one in their settings.';

  /// en: 'No providers yet'
  String get emptyTitle => 'No providers yet';

  /// en: 'Nobody can ask questions until a model is set up. When you add the first model, it becomes the default.'
  String get emptyText => 'Nobody can ask questions until a model is set up. When you add the first model, it becomes the default.';

  /// en: 'Add a model to a provider. Nobody can ask questions until there is one.'
  String get noModels => 'Add a model to a provider. Nobody can ask questions until there is one.';

  /// en: 'There is no default model. Users who did not choose a model in their settings cannot ask questions until you make one the default ({icon}).'
  String noDefault({required Object icon}) =>
      'There is no default model. Users who did not choose a model in their settings cannot ask questions until you make one the default (${icon}).';

  /// en: 'Edit provider'
  String get editProvider => 'Edit provider';

  /// en: 'Delete provider'
  String get deleteProvider => 'Delete provider';

  /// en: 'Default model'
  String get defaultModel => 'Default model';

  /// en: 'Make default'
  String get makeDefault => 'Make default';

  /// en: '{input} in / {output} out'
  String price({required Object input, required Object output}) => '${input} in / ${output} out';

  /// en: 'Cache read {read}, cache write {write}'
  String cachePrices({required Object read, required Object write}) => 'Cache read ${read}, cache write ${write}';

  /// en: 'Not set'
  String get notSet => 'Not set';

  /// en: 'Edit model'
  String get editModel => 'Edit model';

  /// en: 'Delete model'
  String get deleteModel => 'Delete model';

  /// en: 'No models yet.'
  String get noModelsYet => 'No models yet.';

  /// en: 'Fetch models'
  String get fetchModels => 'Fetch models';

  /// en: 'Add model'
  String get addModel => 'Add model';

  /// en: 'Delete Provider'
  String get deleteProviderTitle => 'Delete Provider';

  /// en: '(one) {The provider {name} will be deleted, together with its model. Users who chose one of them fall back to the default model.} (other) {The provider {name} will be deleted, together with its {count} models. Users who chose one of them fall back to the default model.}'
  String deleteProviderText({required num count, required Object name}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'The provider ${name} will be deleted, together with its model. Users who chose one of them fall back to the default model.',
    other: 'The provider ${name} will be deleted, together with its ${count} models. Users who chose one of them fall back to the default model.',
  );

  /// en: 'It has the default model, so there will be no default model afterwards.'
  String get deleteProviderHasDefault => 'It has the default model, so there will be no default model afterwards.';

  /// en: 'Delete Model'
  String get deleteModelTitle => 'Delete Model';

  /// en: 'The model {name} will be deleted. Users who chose it fall back to the default model.'
  String deleteModelText({required Object name}) => 'The model ${name} will be deleted. Users who chose it fall back to the default model.';

  /// en: 'It is the default model, so there will be no default model afterwards.'
  String get deleteModelIsDefault => 'It is the default model, so there will be no default model afterwards.';

  /// en: 'Continue?'
  String get kContinue => 'Continue?';

  /// en: 'Provider updated.'
  String get providerUpdated => 'Provider updated.';

  /// en: 'Provider created.'
  String get providerCreated => 'Provider created.';

  /// en: 'Provider deleted.'
  String get providerDeleted => 'Provider deleted.';

  /// en: 'Model updated.'
  String get modelUpdated => 'Model updated.';

  /// en: '(one) {Model added.} (other) {{count} models added.}'
  String modelsAdded({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'Model added.',
    other: '${count} models added.',
  );

  /// en: 'Model deleted.'
  String get modelDeleted => 'Model deleted.';

  /// en: 'Added {added} of {total} models. {error}'
  String partlyAdded({required Object added, required Object total, required Object error}) => 'Added ${added} of ${total} models. ${error}';

  /// en: 'Added {added} of {total} models. {error} (and {more} more)'
  String partlyAddedMore({required Object added, required Object total, required Object error, required Object more}) =>
      'Added ${added} of ${total} models. ${error} (and ${more} more)';

  /// en: 'Default model changed.'
  String get defaultChanged => 'Default model changed.';

  /// en: 'Could not load the providers: {error}'
  String loadFailed({required Object error}) => 'Could not load the providers: ${error}';

  /// en: 'Could not create the provider: {error}'
  String createProviderFailed({required Object error}) => 'Could not create the provider: ${error}';

  /// en: 'Could not save the provider: {error}'
  String saveProviderFailed({required Object error}) => 'Could not save the provider: ${error}';

  /// en: 'Could not delete the provider: {error}'
  String deleteProviderFailed({required Object error}) => 'Could not delete the provider: ${error}';

  /// en: 'Could not add the model: {error}'
  String addModelFailed({required Object error}) => 'Could not add the model: ${error}';

  /// en: 'Could not save the model: {error}'
  String saveModelFailed({required Object error}) => 'Could not save the model: ${error}';

  /// en: 'Could not delete the model: {error}'
  String deleteModelFailed({required Object error}) => 'Could not delete the model: ${error}';

  /// en: 'Could not change the default model: {error}'
  String setDefaultFailed({required Object error}) => 'Could not change the default model: ${error}';
}

// Path: base.admin.llm.providerDialog
class Translations$base$admin$llm$providerDialog$en {
  Translations$base$admin$llm$providerDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Edit Provider'
  String get editTitle => 'Edit Provider';

  /// en: 'API format'
  String get apiFormat => 'API format';

  /// en: 'Currency'
  String get currency => 'Currency';

  /// en: 'Base URL'
  String get baseUrl => 'Base URL';

  /// en: 'API key'
  String get apiKey => 'API key';

  /// en: '(currently {key})'
  String currentKey({required Object key}) => '(currently ${key})';

  /// en: 'none'
  String get keyNone => 'none';

  /// en: 'set'
  String get keySet => 'set';

  /// en: 'Keep current key'
  String get keepKey => 'Keep current key';

  /// en: 'Remove key'
  String get removeKey => 'Remove key';

  /// en: 'No key'
  String get noKey => 'No key';

  /// en: 'Set new key'
  String get setKey => 'Set new key';

  /// en: 'New API key'
  String get newKey => 'New API key';

  /// en: 'The base URL now points to another host, so the current key cannot be kept. Set a new key, or remove it if the new server needs none.'
  String get hostChanged =>
      'The base URL now points to another host, so the current key cannot be kept. Set a new key, or remove it if the new server needs none.';

  /// en: 'Third-party servers'
  String get thirdParty => 'Third-party servers';

  /// en: '1 to {max} characters.'
  String nameLength({required Object max}) => '1 to ${max} characters.';

  /// en: 'Missing API key'
  String get missingApiKey => 'Missing API key';
}

// Path: base.admin.llm.modelDialog
class Translations$base$admin$llm$modelDialog$en {
  Translations$base$admin$llm$modelDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Edit Model'
  String get editTitle => 'Edit Model';

  /// en: 'New Model for {provider}'
  String newTitle({required Object provider}) => 'New Model for ${provider}';

  /// en: 'API name'
  String get apiName => 'API name';

  /// en: 'Display name'
  String get displayName => 'Display name';

  /// en: 'Max output tokens'
  String get maxOutputTokens => 'Max output tokens';

  /// en: 'The provider has no currency, so its models have no prices. Set one for the provider to enter them.'
  String get noCurrency => 'The provider has no currency, so its models have no prices. Set one for the provider to enter them.';

  /// en: 'Shows the cost of each answer. Leave input and output empty to show none.'
  String get priceHint => 'Shows the cost of each answer. Leave input and output empty to show none.';

  /// en: 'Cache read'
  String get cacheRead => 'Cache read';

  /// en: 'Cache write'
  String get cacheWrite => 'Cache write';

  /// en: 'Same as input'
  String get sameAsInput => 'Same as input';

  /// en: 'There is no default model yet, so this model becomes the default.'
  String get becomesDefault => 'There is no default model yet, so this model becomes the default.';

  /// en: 'Must be a positive whole number.'
  String get tokensInvalid => 'Must be a positive whole number.';

  /// en: 'A number up to {max} with at most {decimals} decimals.'
  String priceInvalid({required Object max, required Object decimals}) => 'A number up to ${max} with at most ${decimals} decimals.';

  /// en: 'Missing API name'
  String get missingApiName => 'Missing API name';

  /// en: 'API name must be at most {max} characters long'
  String apiNameTooLong({required Object max}) => 'API name must be at most ${max} characters long';

  /// en: 'Display name must be at most {max} characters long'
  String displayNameTooLong({required Object max}) => 'Display name must be at most ${max} characters long';

  /// en: 'Max output tokens must be a positive whole number'
  String get maxOutputTokensInvalid => 'Max output tokens must be a positive whole number';

  /// en: 'Prices must be numbers up to {max} with at most {decimals} decimals'
  String pricesInvalid({required Object max, required Object decimals}) => 'Prices must be numbers up to ${max} with at most ${decimals} decimals';

  /// en: 'Set both input and output price, or neither'
  String get inputOutputBoth => 'Set both input and output price, or neither';

  /// en: 'Cache prices require input and output prices'
  String get cacheRequiresPrices => 'Cache prices require input and output prices';
}

// Path: base.admin.llm.remoteModelsDialog
class Translations$base$admin$llm$remoteModelsDialog$en {
  Translations$base$admin$llm$remoteModelsDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Models of {name}'
  String title({required Object name}) => 'Models of ${name}';

  /// en: 'Asking the server for its models…'
  String get fetching => 'Asking the server for its models…';

  /// en: 'You can still add the models by name.'
  String get addByNameHint => 'You can still add the models by name.';

  /// en: 'The server lists no models.'
  String get noModels => 'The server lists no models.';

  /// en: 'Choose the models to add. They must support streaming and tool calling. Prices and max output tokens can be set afterwards by editing each model.'
  String get intro =>
      'Choose the models to add. They must support streaming and tool calling. Prices and max output tokens can be set afterwards by editing each model.';

  /// en: 'Select all'
  String get selectAll => 'Select all';

  /// en: 'Select all {count} matches'
  String selectAllMatches({required Object count}) => 'Select all ${count} matches';

  /// en: 'No model matches “{query}”.'
  String noMatch({required Object query}) => 'No model matches “${query}”.';

  /// en: 'There is no default model yet, so the first model added becomes the default.'
  String get becomesDefault => 'There is no default model yet, so the first model added becomes the default.';

  /// en: 'Add by name'
  String get addByName => 'Add by name';

  /// en: '(one) {Add 1 model} (other) {Add {count} models}'
  String addModels({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: 'Add 1 model',
    other: 'Add ${count} models',
  );
}

// Path: base.admin.config.page
class Translations$base$admin$config$page$en {
  Translations$base$admin$config$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Overrides are stored in the database, so they survive restarts of the server.'
  String get stored => 'Overrides are stored in the database, so they survive restarts of the server.';

  /// en: 'We recommend {envVars}, so the setup stays declarative in one place. Overrides are meant for quick testing.'
  String recommendEnv({required Object envVars}) =>
      'We recommend ${envVars}, so the setup stays declarative in one place. Overrides are meant for quick testing.';

  /// en: 'environment variables'
  String get envVars => 'environment variables';

  /// en: 'Changing the OCR settings converts all documents again, one at a time. Until then, their earlier text is used.'
  String get ocrHint => 'Changing the OCR settings converts all documents again, one at a time. Until then, their earlier text is used.';

  /// en: 'Key'
  String get key => 'Key';

  /// en: 'Env'
  String get env => 'Env';

  /// en: 'Override'
  String get kOverride => 'Override';

  /// en: 'No config'
  String get noConfig => 'No config';

  /// en: 'not set'
  String get notSet => 'not set';

  /// en: 'Env only'
  String get envOnly => 'Env only';

  /// en: 'Use the env value'
  String get useEnv => 'Use the env value';

  /// en: 'Config updated.'
  String get updated => 'Config updated.';

  /// en: 'Could not load the config: {error}'
  String loadFailed({required Object error}) => 'Could not load the config: ${error}';

  /// en: 'Could not save the override: {error}'
  String saveFailed({required Object error}) => 'Could not save the override: ${error}';
}

// Path: base.admin.config.overrideDialog
class Translations$base$admin$config$overrideDialog$en {
  Translations$base$admin$config$overrideDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Env: {value}'
  String env({required Object value}) => 'Env: ${value}';

  /// en: 'Value'
  String get value => 'Value';

  /// en: 'Clear to use the env value'
  String get clearHint => 'Clear to use the env value';

  /// en: 'Leave empty to use the env value'
  String get emptyHint => 'Leave empty to use the env value';
}

// Path: base.admin.extraction.page
class Translations$base$admin$extraction$page$en {
  Translations$base$admin$extraction$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(one) {{count} Document} (other) {{count} Documents}'
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    count,
    one: '${count} Document',
    other: '${count} Documents',
  );

  /// en: 'The OCR settings are part of the {config}. Changing them converts all documents again.'
  String ocrSettings({required Object config}) => 'The OCR settings are part of the ${config}. Changing them converts all documents again.';

  /// en: 'config'
  String get configLink => 'config';

  /// en: 'The OCR service is unavailable'
  String get pausedTitle => 'The OCR service is unavailable';

  /// en: 'Conversions are paused until {time}.'
  String pausedUntil({required Object time}) => 'Conversions are paused until ${time}.';

  /// en: 'Now'
  String get now => 'Now';

  /// en: 'Converting {path}, started {started}'
  String converting({required Object path, required Object started}) => 'Converting ${path}, started ${started}';

  /// en: 'Converting {path} (attached to a chat), started {started}'
  String convertingAttachment({required Object path, required Object started}) => 'Converting ${path} (attached to a chat), started ${started}';

  /// en: 'Converting {path} in {repository} ({owner}), started {started}'
  String convertingRepository({required Object path, required Object repository, required Object owner, required Object started}) =>
      'Converting ${path} in ${repository} (${owner}), started ${started}';

  /// en: 'Paused'
  String get statusPaused => 'Paused';

  /// en: 'Waiting for the next document'
  String get statusWaiting => 'Waiting for the next document';

  /// en: 'Idle, no documents are waiting'
  String get statusIdle => 'Idle, no documents are waiting';

  /// en: '{count} total'
  String total({required Object count}) => '${count} total';

  /// en: '{count} converted'
  String converted({required Object count}) => '${count} converted';

  /// en: '{count} failed'
  String failed({required Object count}) => '${count} failed';

  /// en: '{count} waiting'
  String waiting({required Object count}) => '${count} waiting';

  /// en: '{count} not available'
  String notAvailable({required Object count}) => '${count} not available';

  /// en: 'Extractor'
  String get extractor => 'Extractor';

  /// en: 'Convert again'
  String get convertAgain => 'Convert again';

  /// en: 'The document is converted again.'
  String get retried => 'The document is converted again.';

  /// en: 'Could not load the documents: {error}'
  String loadFailed({required Object error}) => 'Could not load the documents: ${error}';

  /// en: 'Could not convert the document again: {error}'
  String retryFailed({required Object error}) => 'Could not convert the document again: ${error}';
}

// Path: flutter.settings.preferences.modelSheet
class Translations$flutter$settings$preferences$modelSheet$en {
  Translations$flutter$settings$preferences$modelSheet$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'None configured'
  String get noneConfigured => 'None configured';
}

// Path: flutter.admin.users.page
class Translations$flutter$admin$users$page$en {
  Translations$flutter$admin$users$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Repolupe on this device has only one user, so no users can be added. To share chats and repositories with others, use a Repolupe server.'
  String get localOnly =>
      'Repolupe on this device has only one user, so no users can be added. To share chats and repositories with others, use a Repolupe server.';

  /// en: 'No users match your search.'
  String get noMatch => 'No users match your search.';
}

// Path: flutter.admin.users.userPage
class Translations$flutter$admin$users$userPage$en {
  Translations$flutter$admin$users$userPage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Login'
  String get login => 'Login';

  /// en: 'Allowed'
  String get loginAllowed => 'Allowed';

  /// en: 'Disabled (signed out everywhere)'
  String get loginDisabled => 'Disabled (signed out everywhere)';

  /// en: 'Can manage their own and share them'
  String get repositoriesManage => 'Can manage their own and share them';

  /// en: 'Read only (can only ask about repositories shared with them)'
  String get repositoriesReadOnly => 'Read only (can only ask about repositories shared with them)';

  /// en: 'User name and email'
  String get identity => 'User name and email';

  /// en: 'The user can change them'
  String get identityEditable => 'The user can change them';

  /// en: 'Fixed (only admins can change them)'
  String get identityFixed => 'Fixed (only admins can change them)';

  /// en: 'Must be changed at the next login'
  String get passwordMustChange => 'Must be changed at the next login';
}

// Path: flutter.admin.users.form
class Translations$flutter$admin$users$form$en {
  Translations$flutter$admin$users$form$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Admins can be renamed, but never restricted.'
  String get adminNote => 'Admins can be renamed, but never restricted.';
}

// Path: flutter.admin.users.flags
class Translations$flutter$admin$users$flags$en {
  Translations$flutter$admin$users$flags$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Repositories read only'
  String get repositoriesReadOnly => 'Repositories read only';

  /// en: 'Fixed user name and email'
  String get identityFixed => 'Fixed user name and email';
}

// Path: flutter.admin.llm.page
class Translations$flutter$admin$llm$page$en {
  Translations$flutter$admin$llm$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'None'
  String get apiKeyNone => 'None';

  /// en: 'None (its models have no prices)'
  String get currencyNone => 'None (its models have no prices)';

  /// en: 'Models'
  String get models => 'Models';
}

// Path: flutter.admin.llm.namePicker
class Translations$flutter$admin$llm$namePicker$en {
  Translations$flutter$admin$llm$namePicker$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Choose provider'
  String get title => 'Choose provider';

  /// en: 'Search or enter a name'
  String get searchHint => 'Search or enter a name';

  /// en: 'Use “{name}”'
  String useName({required Object name}) => 'Use “${name}”';
}

// Path: flutter.admin.llm.providerForm
class Translations$flutter$admin$llm$providerForm$en {
  Translations$flutter$admin$llm$providerForm$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Clear currency'
  String get clearCurrency => 'Clear currency';

  /// en: 'Show key'
  String get showKey => 'Show key';

  /// en: 'Hide key'
  String get hideKey => 'Hide key';
}

// Path: flutter.admin.llm.modelForm
class Translations$flutter$admin$llm$modelForm$en {
  Translations$flutter$admin$llm$modelForm$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'The model id sent to the API. At most {max} characters.'
  String apiNameHint({required Object max}) => 'The model id sent to the API. At most ${max} characters.';

  /// en: 'Display name (optional)'
  String get displayNameOptional => 'Display name (optional)';

  /// en: 'Shown to users instead of the API name. At most {max} characters.'
  String displayNameHint({required Object max}) => 'Shown to users instead of the API name. At most ${max} characters.';

  /// en: 'Max output tokens (optional)'
  String get maxOutputTokensOptional => 'Max output tokens (optional)';

  /// en: 'Leave empty for the default of the API format.'
  String get maxOutputTokensHint => 'Leave empty for the default of the API format.';
}

// Path: flutter.admin.config.page
class Translations$flutter$admin$config$page$en {
  Translations$flutter$admin$config$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Only runtime settings can be overridden; the others need a restart.'
  String get runtimeOnly => 'Only runtime settings can be overridden; the others need a restart.';

  /// en: 'Runtime'
  String get runtime => 'Runtime';

  /// en: 'Override: {value}'
  String overrideValue({required Object value}) => 'Override: ${value}';
}

// Path: flutter.admin.config.overrideDialog
class Translations$flutter$admin$config$overrideDialog$en {
  Translations$flutter$admin$config$overrideDialog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Remove override'
  String get remove => 'Remove override';
}

// Path: flutter.admin.config.mistralKeySheet
class Translations$flutter$admin$config$mistralKeySheet$en {
  Translations$flutter$admin$config$mistralKeySheet$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Used when OCR_ENGINE is mistral.'
  String get intro => 'Used when OCR_ENGINE is mistral.';

  /// en: 'Remove key'
  String get remove => 'Remove key';
}

// Path: flutter.admin.extraction.page
class Translations$flutter$admin$extraction$page$en {
  Translations$flutter$admin$extraction$page$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Load more ({remaining} remaining)'
  String loadMore({required Object remaining}) => 'Load more (${remaining} remaining)';
}
