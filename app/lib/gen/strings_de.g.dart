///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';

import 'strings.g.dart';

// Path: <root>
class TranslationsDe extends Translations with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsDe({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.de,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

  /// Metadata for the translations of <de>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final TranslationsDe _root = this; // ignore: unused_field

  @override
  TranslationsDe $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsDe(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$base$de base = _Translations$base$de._(_root);
  @override
  late final _Translations$flutter$de flutter = _Translations$flutter$de._(_root);
}

// Path: base
class _Translations$base$de extends Translations$base$en {
  _Translations$base$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$base$common$de common = _Translations$base$common$de._(_root);
  @override
  late final _Translations$base$errors$de errors = _Translations$base$errors$de._(_root);
  @override
  late final _Translations$base$status$de status = _Translations$base$status$de._(_root);
  @override
  late final _Translations$base$user$de user = _Translations$base$user$de._(_root);
  @override
  late final _Translations$base$app$de app = _Translations$base$app$de._(_root);
  @override
  late final _Translations$base$login$de login = _Translations$base$login$de._(_root);
  @override
  late final _Translations$base$chat$de chat = _Translations$base$chat$de._(_root);
  @override
  late final _Translations$base$settings$de settings = _Translations$base$settings$de._(_root);
  @override
  late final _Translations$base$repositories$de repositories = _Translations$base$repositories$de._(_root);
  @override
  late final _Translations$base$documents$de documents = _Translations$base$documents$de._(_root);
  @override
  late final _Translations$base$admin$de admin = _Translations$base$admin$de._(_root);
}

// Path: flutter
class _Translations$flutter$de extends Translations$flutter$en {
  _Translations$flutter$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$common$de common = _Translations$flutter$common$de._(_root);
  @override
  late final _Translations$flutter$setup$de setup = _Translations$flutter$setup$de._(_root);
  @override
  late final _Translations$flutter$account$de account = _Translations$flutter$account$de._(_root);
  @override
  late final _Translations$flutter$chat$de chat = _Translations$flutter$chat$de._(_root);
  @override
  late final _Translations$flutter$settings$de settings = _Translations$flutter$settings$de._(_root);
  @override
  late final _Translations$flutter$validation$de validation = _Translations$flutter$validation$de._(_root);
  @override
  late final _Translations$flutter$themeMode$de themeMode = _Translations$flutter$themeMode$de._(_root);
  @override
  late final _Translations$flutter$repositories$de repositories = _Translations$flutter$repositories$de._(_root);
  @override
  late final _Translations$flutter$documents$de documents = _Translations$flutter$documents$de._(_root);
  @override
  late final _Translations$flutter$format$de format = _Translations$flutter$format$de._(_root);
  @override
  late final _Translations$flutter$admin$de admin = _Translations$flutter$admin$de._(_root);
}

// Path: base.common
class _Translations$base$common$de extends Translations$base$common$en {
  _Translations$base$common$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get save => 'Speichern';
  @override
  String get cancel => 'Abbrechen';
  @override
  String get delete => 'Löschen';
  @override
  String get close => 'Schließen';
  @override
  String get edit => 'Bearbeiten';
  @override
  String get retry => 'Erneut versuchen';
  @override
  String get search => 'Suchen';
  @override
  String get refresh => 'Aktualisieren';
  @override
  String get download => 'Herunterladen';
  @override
  String get name => 'Name';
  @override
  String get model => 'Modell';
  @override
  String get status => 'Status';
  @override
  String get error => 'Fehler';
  @override
  String get unknownError => 'Unbekannter Fehler';
  @override
  String get required => 'Pflichtfeld.';
  @override
  String get loading => 'Wird geladen...';
  @override
  String get actions => 'Aktionen';
  @override
  String get kDefault => 'Standard';
  @override
  String get added => 'Hinzugefügt';
  @override
  String get repository => 'Repository';
  @override
  String get input => 'Eingabe';
  @override
  String get output => 'Ausgabe';
  @override
  String get missingName => 'Name fehlt';
  @override
  String nameTooLong({required Object max}) => 'Der Name darf höchstens ${max} Zeichen lang sein';
}

// Path: base.errors
class _Translations$base$errors$de extends Translations$base$errors$en {
  _Translations$base$errors$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String invalidResponse({required Object status}) => 'Unerwartete Antwort vom Server (${status}).';
  @override
  String get unreachable => 'Der Server ist nicht erreichbar.';
  @override
  String get internalError => 'Auf dem Server ist ein Fehler aufgetreten.';
  @override
  String get validationError => 'Die Anfrage ist ungültig.';
  @override
  String get unsupportedMediaType => 'Die Anfrage hat ein nicht unterstütztes Format.';
  @override
  String get unauthorized => 'Du bist nicht angemeldet.';
  @override
  String get forbidden => 'Dazu bist du nicht berechtigt.';
  @override
  String get notFound => 'Nicht gefunden, es wurde vielleicht gelöscht.';
  @override
  String get conflict => 'Es wurde gleichzeitig geändert, bitte versuche es erneut.';
  @override
  String get rateLimited => 'Zu viele Anfragen, bitte versuche es später erneut.';
  @override
  String get userNameTaken => 'Es gibt bereits einen Benutzer mit diesem Benutzernamen.';
  @override
  String get emailTaken => 'Es gibt bereits einen Benutzer mit dieser E-Mail.';
  @override
  String get nameTaken => 'Dieser Name ist bereits vergeben.';
  @override
  String get repoNotFound => 'Das Repository wurde auf dem Remote nicht gefunden.';
  @override
  String get branchNotFound => 'Der Branch wurde auf dem Remote nicht gefunden.';
  @override
  String get authFailed => 'Die Zugangsdaten wurden abgelehnt, prüfe den Zugriffstoken oder API-Schlüssel.';
  @override
  String get tokenRequired =>
      'Der Host hat sich geändert, daher kann der gespeicherte Token oder API-Schlüssel nicht behalten werden. Setze einen neuen oder entferne ihn.';
  @override
  String get remoteUnreachable => 'Der Remote-Server ist nicht erreichbar oder hat mit einem Fehler geantwortet.';
  @override
  String get unknownRepository => 'Ein Repository existiert nicht mehr.';
  @override
  String get unknownUser => 'Es gibt keinen Benutzer mit diesem Benutzernamen oder dieser E-Mail.';
  @override
  String get generationInProgress => 'In diesem Chat wird bereits eine Antwort erstellt.';
  @override
  String get notRetryable => 'Nur eine fehlgeschlagene oder abgebrochene Antwort am Ende des Chats kann wiederholt werden.';
  @override
  String get wrongPassword => 'Das aktuelle Passwort ist falsch.';
  @override
  String get samePassword => 'Das neue Passwort muss sich vom aktuellen unterscheiden.';
  @override
  String get passwordChangeRequired => 'Du musst zuerst dein Passwort ändern.';
  @override
  String get unknownModel => 'Das Modell ist nicht mehr verfügbar.';
  @override
  String get noModelConfigured => 'Es ist kein Sprachmodell eingerichtet, bitte einen Admin, eines hinzuzufügen.';
  @override
  String get unavailable => 'Der Server ist nicht verfügbar, bitte versuche es später erneut.';
  @override
  String get fileUnavailable => 'Die Datei ist nicht mehr verfügbar.';
  @override
  String get unknownAttachment => 'Der Anhang existiert nicht oder wurde bereits gesendet.';
}

// Path: base.status
class _Translations$base$status$de extends Translations$base$status$en {
  _Translations$base$status$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get pending => 'Ausstehend';
  @override
  String get syncing => 'Wird synchronisiert';
  @override
  String get ready => 'Bereit';
  @override
  String get failed => 'Fehlgeschlagen';
  @override
  String get waiting => 'Wartet';
  @override
  String get converting => 'Wird umgewandelt';
  @override
  String get notAvailable => 'Nicht verfügbar';
  @override
  String get converted => 'Umgewandelt';
}

// Path: base.user
class _Translations$base$user$de extends Translations$base$user$en {
  _Translations$base$user$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get userName => 'Benutzername';
  @override
  String get email => 'E-Mail';
  @override
  String get emailOptional => 'E-Mail (optional)';
  @override
  String get userNameOrEmail => 'Benutzername oder E-Mail';
  @override
  String get password => 'Passwort';
  @override
  String passwordHint({required Object min, required Object max}) => '${min} bis ${max} Zeichen';
  @override
  String get currentPassword => 'Aktuelles Passwort';
  @override
  String get newPassword => 'Neues Passwort';
  @override
  String get confirmPassword => 'Neues Passwort bestätigen';
  @override
  String get missingPassword => 'Passwort fehlt';
  @override
  String passwordLengthInvalid({required Object min, required Object max}) => 'Das Passwort muss ${min} bis ${max} Zeichen lang sein';
  @override
  String newPasswordLengthInvalid({required Object min, required Object max}) => 'Das neue Passwort muss ${min} bis ${max} Zeichen lang sein.';
  @override
  String get passwordMismatch => 'Die neuen Passwörter stimmen nicht überein.';
  @override
  String get wrongPassword => 'Das aktuelle Passwort ist falsch';
  @override
  String get samePassword => 'Das neue Passwort muss sich vom aktuellen unterscheiden';
  @override
  String get role => 'Rolle';
  @override
  String get roleAdmin => 'Admin';
  @override
  String get roleUser => 'Benutzer';
  @override
  String get missingUserName => 'Benutzername fehlt';
  @override
  String userNameInvalid({required Object max}) => 'Der Benutzername muss aus 1 bis ${max} Buchstaben, Ziffern, \'.\', \'_\' oder \'-\' bestehen';
  @override
  String get emailInvalid => 'Ungültige E-Mail-Adresse';
  @override
  String get userNameTaken => 'Es gibt bereits einen Benutzer mit diesem Benutzernamen';
  @override
  String get emailTaken => 'Es gibt bereits einen Benutzer mit dieser E-Mail';
}

// Path: base.app
class _Translations$base$app$de extends Translations$base$app$en {
  _Translations$base$app$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get logoAlt => 'Repolupe-Logo';
  @override
  late final _Translations$base$app$navigation$de navigation = _Translations$base$app$navigation$de._(_root);
  @override
  late final _Translations$base$app$mainContainer$de mainContainer = _Translations$base$app$mainContainer$de._(_root);
  @override
  late final _Translations$base$app$genericDeleteDialog$de genericDeleteDialog = _Translations$base$app$genericDeleteDialog$de._(_root);
}

// Path: base.login
class _Translations$base$login$de extends Translations$base$login$en {
  _Translations$base$login$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get login => 'Anmelden';
  @override
  String get wrongCredentials => 'Falscher Benutzername oder falsches Passwort';
  @override
  late final _Translations$base$login$changePasswordPage$de changePasswordPage = _Translations$base$login$changePasswordPage$de._(_root);
  @override
  String loginFailed({required Object error}) => 'Anmeldung fehlgeschlagen: ${error}';
}

// Path: base.chat
class _Translations$base$chat$de extends Translations$base$chat$en {
  _Translations$base$chat$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chats';
  @override
  String get noChats => 'Noch keine Chats';
  @override
  String get placeholder => 'Nachricht';
  @override
  String get unknownModel => 'Das ausgewählte Modell ist nicht mehr verfügbar.';
  @override
  String get unknownAttachment => 'Die angehängte Datei ist nicht mehr verfügbar, bitte hänge sie erneut an.';
  @override
  String get noModelConfigured => 'Es ist kein Sprachmodell eingerichtet. Bitte einen Admin, einen LLM-Anbieter hinzuzufügen.';
  @override
  String get rateLimited => 'Es werden gerade zu viele Antworten erstellt. Bitte warte, bis eine fertig ist.';
  @override
  String get allRepositories => 'Alle Repositories';
  @override
  String repositoryCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    zero: 'Kein Repository',
    one: '1 Repository',
    other: '${count} Repositories',
  );
  @override
  String moveCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: '1 Verschiebung',
    other: '${count} Verschiebungen',
  );
  @override
  String get temporary => 'Temporärer Chat';
  @override
  late final _Translations$base$chat$startPage$de startPage = _Translations$base$chat$startPage$de._(_root);
  @override
  late final _Translations$base$chat$page$de page = _Translations$base$chat$page$de._(_root);
  @override
  late final _Translations$base$chat$messageInput$de messageInput = _Translations$base$chat$messageInput$de._(_root);
  @override
  late final _Translations$base$chat$assistantMessage$de assistantMessage = _Translations$base$chat$assistantMessage$de._(_root);
  @override
  late final _Translations$base$chat$userMessage$de userMessage = _Translations$base$chat$userMessage$de._(_root);
  @override
  late final _Translations$base$chat$toolCallList$de toolCallList = _Translations$base$chat$toolCallList$de._(_root);
  @override
  late final _Translations$base$chat$toolCallLabel$de toolCallLabel = _Translations$base$chat$toolCallLabel$de._(_root);
  @override
  late final _Translations$base$chat$toolCallDialog$de toolCallDialog = _Translations$base$chat$toolCallDialog$de._(_root);
  @override
  late final _Translations$base$chat$proposedCommitPanel$de proposedCommitPanel = _Translations$base$chat$proposedCommitPanel$de._(_root);
  @override
  late final _Translations$base$chat$renameDialog$de renameDialog = _Translations$base$chat$renameDialog$de._(_root);
  @override
  late final _Translations$base$chat$usageDialog$de usageDialog = _Translations$base$chat$usageDialog$de._(_root);
  @override
  String loadFailed({required Object error}) => 'Die Chats konnten nicht geladen werden: ${error}';
}

// Path: base.settings
class _Translations$base$settings$de extends Translations$base$settings$en {
  _Translations$base$settings$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Einstellungen';
  @override
  late final _Translations$base$settings$page$de page = _Translations$base$settings$page$de._(_root);
  @override
  late final _Translations$base$settings$account$de account = _Translations$base$settings$account$de._(_root);
  @override
  late final _Translations$base$settings$profile$de profile = _Translations$base$settings$profile$de._(_root);
  @override
  late final _Translations$base$settings$preferences$de preferences = _Translations$base$settings$preferences$de._(_root);
}

// Path: base.repositories
class _Translations$base$repositories$de extends Translations$base$repositories$en {
  _Translations$base$repositories$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Repositories';
  @override
  String get newRepository => 'Neues Repository';
  @override
  String get size => 'Größe';
  @override
  String get share => 'Teilen';
  @override
  String get remote => 'Remote';
  @override
  String get local => 'Lokal';
  @override
  String get remoteUrl => 'Remote-URL';
  @override
  String get branch => 'Branch';
  @override
  String get description => 'Beschreibung';
  @override
  String get accessToken => 'Zugriffstoken';
  @override
  String get syncInterval => 'Synchronisierungsintervall';
  @override
  String get allowCommits => 'Schreibzugriff aktivieren';
  @override
  String descriptionTooLong({required Object max}) => 'Die Beschreibung darf höchstens ${max} Zeichen lang sein';
  @override
  String get missingRemoteUrl => 'Remote-URL fehlt';
  @override
  String get missingBranch => 'Branch fehlt';
  @override
  late final _Translations$base$repositories$pollInterval$de pollInterval = _Translations$base$repositories$pollInterval$de._(_root);
  @override
  late final _Translations$base$repositories$listPage$de listPage = _Translations$base$repositories$listPage$de._(_root);
  @override
  late final _Translations$base$repositories$page$de page = _Translations$base$repositories$page$de._(_root);
  @override
  late final _Translations$base$repositories$kindDialog$de kindDialog = _Translations$base$repositories$kindDialog$de._(_root);
  @override
  late final _Translations$base$repositories$createDialog$de createDialog = _Translations$base$repositories$createDialog$de._(_root);
  @override
  late final _Translations$base$repositories$editDialog$de editDialog = _Translations$base$repositories$editDialog$de._(_root);
  @override
  late final _Translations$base$repositories$usersCard$de usersCard = _Translations$base$repositories$usersCard$de._(_root);
  @override
  late final _Translations$base$repositories$shareDialog$de shareDialog = _Translations$base$repositories$shareDialog$de._(_root);
}

// Path: base.documents
class _Translations$base$documents$de extends Translations$base$documents$en {
  _Translations$base$documents$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dokumente';
  @override
  String get description => 'Dokumente werden im Hintergrund in Text umgewandelt, damit das Modell sie lesen kann.';
  @override
  String get document => 'Dokument';
  @override
  String get detailsColumn => 'Details';
  @override
  String get noData => 'Keine Dokumente in dieser Kategorie.';
  @override
  late final _Translations$base$documents$card$de card = _Translations$base$documents$card$de._(_root);
  @override
  late final _Translations$base$documents$statusFilter$de statusFilter = _Translations$base$documents$statusFilter$de._(_root);
  @override
  late final _Translations$base$documents$details$de details = _Translations$base$documents$details$de._(_root);
  @override
  String loadFailed({required Object error}) => 'Die Dokumente konnten nicht geladen werden: ${error}';
}

// Path: base.admin
class _Translations$base$admin$de extends Translations$base$admin$en {
  _Translations$base$admin$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$base$admin$users$de users = _Translations$base$admin$users$de._(_root);
  @override
  late final _Translations$base$admin$llm$de llm = _Translations$base$admin$llm$de._(_root);
  @override
  late final _Translations$base$admin$config$de config = _Translations$base$admin$config$de._(_root);
  @override
  late final _Translations$base$admin$extraction$de extraction = _Translations$base$admin$extraction$de._(_root);
}

// Path: flutter.common
class _Translations$flutter$common$de extends Translations$flutter$common$en {
  _Translations$flutter$common$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$common$unsavedChanges$de unsavedChanges = _Translations$flutter$common$unsavedChanges$de._(_root);
}

// Path: flutter.setup
class _Translations$flutter$setup$de extends Translations$flutter$setup$en {
  _Translations$flutter$setup$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get addAccount => 'Konto hinzufügen';
  @override
  String get intro => 'Melde dich bei deinem Repolupe-Server an oder führe Repolupe auf diesem Gerät aus.';
  @override
  String get introRemote => 'Melde dich bei deinem Repolupe-Server an.';
  @override
  String get server => 'Server';
  @override
  String get remoteDescription => 'Melde dich bei einem Repolupe-Server an und nutze seine Repositories und Modelle.';
  @override
  String get localDescription => 'Führe Repolupe in der App aus. Chats und Repositories bleiben auf diesem Gerät.';
}

// Path: flutter.account
class _Translations$flutter$account$de extends Translations$flutter$account$en {
  _Translations$flutter$account$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get thisDevice => 'Dieses Gerät';
  @override
  String get invalidApiUrl => 'Ungültige Serveradresse.';
  @override
  String localStartFailed({required Object message}) => 'Die lokale Instanz konnte nicht gestartet werden: ${message}';
  @override
  String sessionExpired({required Object server}) => 'Deine Sitzung auf ${server} ist abgelaufen. Bitte melde dich erneut an.';
}

// Path: flutter.chat
class _Translations$flutter$chat$de extends Translations$flutter$chat$en {
  _Translations$flutter$chat$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$chat$page$de page = _Translations$flutter$chat$page$de._(_root);
  @override
  late final _Translations$flutter$chat$markdownContent$de markdownContent = _Translations$flutter$chat$markdownContent$de._(_root);
  @override
  late final _Translations$flutter$chat$repositorySheet$de repositorySheet = _Translations$flutter$chat$repositorySheet$de._(_root);
  @override
  late final _Translations$flutter$chat$toolCallPage$de toolCallPage = _Translations$flutter$chat$toolCallPage$de._(_root);
  @override
  late final _Translations$flutter$chat$presentedFilePage$de presentedFilePage = _Translations$flutter$chat$presentedFilePage$de._(_root);
  @override
  late final _Translations$flutter$chat$proposedCommitPage$de proposedCommitPage = _Translations$flutter$chat$proposedCommitPage$de._(_root);
}

// Path: flutter.settings
class _Translations$flutter$settings$de extends Translations$flutter$settings$en {
  _Translations$flutter$settings$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$settings$changePasswordPage$de changePasswordPage = _Translations$flutter$settings$changePasswordPage$de._(_root);
  @override
  late final _Translations$flutter$settings$accountSheet$de accountSheet = _Translations$flutter$settings$accountSheet$de._(_root);
  @override
  late final _Translations$flutter$settings$preferences$de preferences = _Translations$flutter$settings$preferences$de._(_root);
}

// Path: flutter.validation
class _Translations$flutter$validation$de extends Translations$flutter$validation$en {
  _Translations$flutter$validation$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get invalidCurrency => 'Ungültige Währung, erwartet wird ein Code wie USD oder EUR';
}

// Path: flutter.themeMode
class _Translations$flutter$themeMode$de extends Translations$flutter$themeMode$en {
  _Translations$flutter$themeMode$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Design';
  @override
  String get system => 'System';
  @override
  String get light => 'Hell';
  @override
  String get dark => 'Dunkel';
}

// Path: flutter.repositories
class _Translations$flutter$repositories$de extends Translations$flutter$repositories$en {
  _Translations$flutter$repositories$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get statusUnknown => 'Unbekannt';
  @override
  late final _Translations$flutter$repositories$listPage$de listPage = _Translations$flutter$repositories$listPage$de._(_root);
  @override
  late final _Translations$flutter$repositories$page$de page = _Translations$flutter$repositories$page$de._(_root);
  @override
  late final _Translations$flutter$repositories$form$de form = _Translations$flutter$repositories$form$de._(_root);
  @override
  late final _Translations$flutter$repositories$usersCard$de usersCard = _Translations$flutter$repositories$usersCard$de._(_root);
}

// Path: flutter.documents
class _Translations$flutter$documents$de extends Translations$flutter$documents$en {
  _Translations$flutter$documents$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get notSynced => 'Noch nicht synchronisiert';
  @override
  String get noDocuments => 'Keine Dokumente';
  @override
  String showMore({required Object remaining}) => 'Mehr anzeigen (${remaining} weitere)';
  @override
  late final _Translations$flutter$documents$details$de details = _Translations$flutter$documents$details$de._(_root);
}

// Path: flutter.format
class _Translations$flutter$format$de extends Translations$flutter$format$en {
  _Translations$flutter$format$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$format$relative$de relative = _Translations$flutter$format$relative$de._(_root);
}

// Path: flutter.admin
class _Translations$flutter$admin$de extends Translations$flutter$admin$en {
  _Translations$flutter$admin$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$users$de users = _Translations$flutter$admin$users$de._(_root);
  @override
  late final _Translations$flutter$admin$llm$de llm = _Translations$flutter$admin$llm$de._(_root);
  @override
  late final _Translations$flutter$admin$config$de config = _Translations$flutter$admin$config$de._(_root);
  @override
  late final _Translations$flutter$admin$extraction$de extraction = _Translations$flutter$admin$extraction$de._(_root);
}

// Path: base.app.navigation
class _Translations$base$app$navigation$de extends Translations$base$app$navigation$en {
  _Translations$base$app$navigation$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get expand => 'Ausklappen';
  @override
  String get expandNavigation => 'Navigation ausklappen';
  @override
  String get collapse => 'Einklappen';
  @override
  String get collapseNavigation => 'Navigation einklappen';
  @override
  String get newChat => 'Neuer Chat';
  @override
  String get allChats => 'Alle Chats';
}

// Path: base.app.mainContainer
class _Translations$base$app$mainContainer$de extends Translations$base$app$mainContainer$en {
  _Translations$base$app$mainContainer$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String quotedTitle({required Object title}) => '„${title}“';
}

// Path: base.app.genericDeleteDialog
class _Translations$base$app$genericDeleteDialog$de extends Translations$base$app$genericDeleteDialog$en {
  _Translations$base$app$genericDeleteDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String verifyPrompt({required Object verify}) => 'Gib zur Bestätigung „${verify}“ in das Feld unten ein:';
  @override
  String get verification => 'Bestätigung';
  @override
  String get mismatch => 'Stimmt nicht überein.';
}

// Path: base.login.changePasswordPage
class _Translations$base$login$changePasswordPage$de extends Translations$base$login$changePasswordPage$en {
  _Translations$base$login$changePasswordPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Passwort ändern';
  @override
  String get submit => 'Passwort ändern';
  @override
  String get logout => 'Abmelden';
}

// Path: base.chat.startPage
class _Translations$base$chat$startPage$de extends Translations$base$chat$startPage$en {
  _Translations$base$chat$startPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get loadFailed => 'Die Repositories konnten nicht geladen werden.';
  @override
  String get noModel => 'Es ist noch kein Sprachmodell eingerichtet, daher können keine Fragen beantwortet werden.';
  @override
  String addProvider({required Object link}) => '${link}, um loszulegen.';
  @override
  String get addProviderLink => 'Füge einen LLM-Anbieter hinzu';
  @override
  String get askAdmin => 'Bitte einen Admin, einen LLM-Anbieter einzurichten.';
  @override
  String get waitForUpload => 'Bitte warte, bis die Datei hochgeladen ist.';
  @override
  String get enterQuestion => 'Bitte gib eine Frage ein.';
  @override
  String get unknownRepository => 'Ein ausgewähltes Repository ist nicht mehr verfügbar.';
}

// Path: base.chat.page
class _Translations$base$chat$page$de extends Translations$base$chat$page$en {
  _Translations$base$chat$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get actions => 'Chat-Aktionen';
  @override
  String get rename => 'Umbenennen';
  @override
  String get deleteTitle => 'Chat löschen';
  @override
  String deleteConfirm({required Object title}) => 'Möchtest du „${title}“ mit allen Nachrichten wirklich löschen?';
  @override
  String get connectionLost => 'Die Verbindung zur Antwort ist abgebrochen. Lade die Seite neu, um es erneut zu versuchen.';
  @override
  String get notFound => 'Chat nicht gefunden';
  @override
  String get renamed => 'Chat umbenannt.';
  @override
  String get deleted => 'Chat gelöscht.';
  @override
  String openFailed({required Object error}) => 'Der Chat konnte nicht geöffnet werden: ${error}';
  @override
  String sendFailed({required Object error}) => 'Die Nachricht konnte nicht gesendet werden: ${error}';
  @override
  String retryFailed({required Object error}) => 'Die Antwort konnte nicht erneut erstellt werden: ${error}';
  @override
  String stopFailed({required Object error}) => 'Die Antwort konnte nicht gestoppt werden: ${error}';
  @override
  String renameFailed({required Object error}) => 'Der Chat konnte nicht umbenannt werden: ${error}';
  @override
  String changeModelFailed({required Object error}) => 'Das Modell konnte nicht geändert werden: ${error}';
  @override
  String deleteFailed({required Object error}) => 'Der Chat konnte nicht gelöscht werden: ${error}';
}

// Path: base.chat.messageInput
class _Translations$base$chat$messageInput$de extends Translations$base$chat$messageInput$en {
  _Translations$base$chat$messageInput$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get stop => 'Stoppen';
  @override
  String get send => 'Senden';
  @override
  String get dropHint => 'Datei hier ablegen, um sie anzuhängen';
  @override
  String fileTooLarge({required Object max}) => 'Die Datei ist zu groß, sie darf höchstens ${max} groß sein.';
  @override
  String uploadFailed({required Object error}) => 'Die Datei konnte nicht hochgeladen werden: ${error}';
  @override
  String get oneFileOnly => 'An eine Nachricht kann nur eine Datei angehängt werden.';
}

// Path: base.chat.assistantMessage
class _Translations$base$chat$assistantMessage$de extends Translations$base$chat$assistantMessage$en {
  _Translations$base$chat$assistantMessage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get thinking => 'Denkt nach…';
  @override
  String get noAnswer => '(Keine Antwort)';
  @override
  String proposedStore({required Object path}) => 'Speichern als ${path} vorgeschlagen';
  @override
  String proposedChange({required Object path}) => 'Vorgeschlagene Änderung an ${path}';
  @override
  String proposedMoves({required Object moves}) => 'Vorgeschlagene Verschiebungen: ${moves}';
  @override
  String get failed => 'Die Antwort konnte nicht erstellt werden.';
  @override
  String get cancelled => 'Abgebrochen';
  @override
  String get showUsage => 'Token-Verbrauch anzeigen';
  @override
  String durationSeconds({required Object seconds}) => '${seconds} s';
  @override
  String durationMinutes({required Object minutes, required Object seconds}) => '${minutes} min ${seconds} s';
}

// Path: base.chat.userMessage
class _Translations$base$chat$userMessage$de extends Translations$base$chat$userMessage$en {
  _Translations$base$chat$userMessage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String download({required Object name}) => '${name} herunterladen';
}

// Path: base.chat.toolCallList
class _Translations$base$chat$toolCallList$de extends Translations$base$chat$toolCallList$en {
  _Translations$base$chat$toolCallList$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get running => 'Liest die Repositories';
  @override
  String used({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: '${count} Tool verwendet',
    other: '${count} Tools verwendet',
  );
  @override
  String usedWithFailed({required num count, required Object failed}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: '${count} Tool verwendet (${failed} fehlgeschlagen)',
    other: '${count} Tools verwendet (${failed} fehlgeschlagen)',
  );
}

// Path: base.chat.toolCallLabel
class _Translations$base$chat$toolCallLabel$de extends Translations$base$chat$toolCallLabel$en {
  _Translations$base$chat$toolCallLabel$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String grepPatternIn({required Object pattern, required Object where}) => '"${pattern}" in ${where}';
  @override
  String grepIn({required Object where}) => 'in ${where}';
}

// Path: base.chat.toolCallDialog
class _Translations$base$chat$toolCallDialog$de extends Translations$base$chat$toolCallDialog$en {
  _Translations$base$chat$toolCallDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get stillRunning => 'Läuft noch.';
  @override
  String get noOutput => 'Keine Ausgabe.';
  @override
  String loadFailed({required Object error}) => 'Der Tool-Aufruf konnte nicht geladen werden: ${error}';
}

// Path: base.chat.proposedCommitPanel
class _Translations$base$chat$proposedCommitPanel$de extends Translations$base$chat$proposedCommitPanel$en {
  _Translations$base$chat$proposedCommitPanel$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get applied => 'Übernommen';
  @override
  String appliedAt({required Object relative, required Object dateTime}) => 'Übernommen ${relative} (${dateTime})';
  @override
  String get more => 'Mehr';
  @override
  String get downloadPatch => 'Als Patch-Datei herunterladen';
  @override
  String get willDelete => 'Diese Datei wird gelöscht.';
  @override
  String get willCreate => 'Diese Datei wird erstellt.';
  @override
  String get removed => 'Entfernt';
  @override
  String get unchangedLines => 'Unveränderte Zeilen';
  @override
  String removedLine({required Object text}) => 'entfernt: ${text}';
  @override
  String addedLine({required Object text}) => 'hinzugefügt: ${text}';
  @override
  String movedTo({required Object from, required Object to}) => '${from} verschoben nach ${to}';
  @override
  String folderFiles({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'Ordner mit 1 Datei',
    other: 'Ordner mit ${count} Dateien',
  );
  @override
  String get noPreview => 'Für diese Art von Datei gibt es keine Vorschau.';
  @override
  String get cannotCommit => 'Nur der Besitzer dieses Repositorys und Benutzer mit Schreibzugriff können Änderungen übernehmen.';
  @override
  String get enableAutoCommit => 'Immer automatisch übernehmen';
  @override
  String get autoCommitTitle => 'Immer automatisch übernehmen?';
  @override
  String get autoCommitText =>
      'Ab jetzt werden Änderungen, die der Assistent vorschlägt, übernommen, sobald seine Antwort fertig ist, ohne dich zu fragen. Diese Änderung wird jetzt übernommen. Du kannst das in deinen Einstellungen wieder ausschalten.';
  @override
  String get autoCommitConfirm => 'Aktivieren und übernehmen';
  @override
  String get apply => 'Änderung übernehmen';
  @override
  String get tryAgain => 'Erneut versuchen';
  @override
  String appliedTo({required Object name}) => 'Änderung an ${name} übernommen';
  @override
  String get appliedMoves => 'Verschiebungen übernommen';
  @override
  String applyFailed({required Object error}) => 'Die Änderung konnte nicht übernommen werden: ${error}';
  @override
  String downloadFailed({required Object error}) => 'Der Patch konnte nicht heruntergeladen werden: ${error}';
}

// Path: base.chat.renameDialog
class _Translations$base$chat$renameDialog$de extends Translations$base$chat$renameDialog$en {
  _Translations$base$chat$renameDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chat umbenennen';
  @override
  String get label => 'Titel';
  @override
  String maxLength({required Object max}) => 'Höchstens ${max} Zeichen.';
}

// Path: base.chat.usageDialog
class _Translations$base$chat$usageDialog$de extends Translations$base$chat$usageDialog$en {
  _Translations$base$chat$usageDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Token-Verbrauch';
  @override
  String get type => 'Art';
  @override
  String get tokens => 'Tokens';
  @override
  String get inputHint => 'Weder aus dem Cache gelesen noch in den Cache geschrieben';
  @override
  String get cacheRead => 'Cache gelesen';
  @override
  String get cacheReadHint => 'Aus dem Cache gelesene Eingabe';
  @override
  String get cacheWrite => 'Cache geschrieben';
  @override
  String get cacheWriteHint => 'In den Cache geschriebene Eingabe';
  @override
  String get outputHint => 'Einschließlich Denkschritten';
  @override
  String get total => 'Gesamt';
  @override
  String get cost => 'Kosten';
}

// Path: base.settings.page
class _Translations$base$settings$page$de extends Translations$base$settings$page$en {
  _Translations$base$settings$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get admin => 'Admin';
  @override
  String get logout => 'Abmelden';
  @override
  String get repositoriesSubtitle => 'Repositories als Wissensbasis hinzufügen und mit anderen Benutzern teilen';
  @override
  String get accountSubtitle => 'Deine Anmeldedaten und dein Passwort';
  @override
  String get profileSubtitle => 'Was der Assistent über dich erfährt';
  @override
  String get preferencesSubtitle => 'Dein Standardmodell und deine Sprache';
  @override
  String get usersSubtitle => 'Benutzer erstellen, ihre Rollen und Berechtigungen festlegen';
  @override
  String get llmSubtitle => 'LLM-Server, ihre Modelle und das Standardmodell konfigurieren';
  @override
  String get extractionSubtitle => 'Die Umwandlung von Dokumenten in Text verfolgen und fehlgeschlagene erneut versuchen';
  @override
  String get configSubtitle => 'Die Serverkonfiguration ansehen und Einstellungen ohne Neustart überschreiben';
}

// Path: base.settings.account
class _Translations$base$settings$account$de extends Translations$base$settings$account$en {
  _Translations$base$settings$account$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Konto';
  @override
  late final _Translations$base$settings$account$page$de page = _Translations$base$settings$account$page$de._(_root);
  @override
  late final _Translations$base$settings$account$changePasswordDialog$de changePasswordDialog =
      _Translations$base$settings$account$changePasswordDialog$de._(_root);
  @override
  late final _Translations$base$settings$account$identityDialog$de identityDialog = _Translations$base$settings$account$identityDialog$de._(_root);
}

// Path: base.settings.profile
class _Translations$base$settings$profile$de extends Translations$base$settings$profile$en {
  _Translations$base$settings$profile$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Profil';
  @override
  String get fullName => 'Vollständiger Name';
  @override
  String get firstName => 'Vorname';
  @override
  String get about => 'Über dich';
  @override
  late final _Translations$base$settings$profile$page$de page = _Translations$base$settings$profile$page$de._(_root);
  @override
  late final _Translations$base$settings$profile$dialog$de dialog = _Translations$base$settings$profile$dialog$de._(_root);
}

// Path: base.settings.preferences
class _Translations$base$settings$preferences$de extends Translations$base$settings$preferences$en {
  _Translations$base$settings$preferences$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Voreinstellungen';
  @override
  String get language => 'Sprache';
  @override
  String browserDefault({required Object locale}) => 'Standard des Browsers (${locale})';
  @override
  String defaultModel({required Object name}) => 'Standard (${name})';
  @override
  String get defaultNone => 'Standard (keines konfiguriert)';
  @override
  late final _Translations$base$settings$preferences$page$de page = _Translations$base$settings$preferences$page$de._(_root);
  @override
  late final _Translations$base$settings$preferences$localeDialog$de localeDialog = _Translations$base$settings$preferences$localeDialog$de._(_root);
  @override
  late final _Translations$base$settings$preferences$modelDialog$de modelDialog = _Translations$base$settings$preferences$modelDialog$de._(_root);
}

// Path: base.repositories.pollInterval
class _Translations$base$repositories$pollInterval$de extends Translations$base$repositories$pollInterval$en {
  _Translations$base$repositories$pollInterval$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get minute => 'Jede Minute';
  @override
  String get minutes5 => 'Alle 5 Minuten';
  @override
  String get minutes15 => 'Alle 15 Minuten';
  @override
  String get hour => 'Jede Stunde';
  @override
  String get hours6 => 'Alle 6 Stunden';
  @override
  String get daily => 'Täglich';
  @override
  String seconds({required Object seconds}) => 'Alle ${seconds} Sekunden';
}

// Path: base.repositories.listPage
class _Translations$base$repositories$listPage$de extends Translations$base$repositories$listPage$en {
  _Translations$base$repositories$listPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    zero: '${count} Repositories',
    one: '${count} Repository',
    other: '${count} Repositories',
  );
  @override
  String get description =>
      'Deine Repositories und die, die mit dir geteilt wurden. In Chats liest das Modell ihre Dateien, um deine Fragen zu beantworten.';
  @override
  String get emptyTitle => 'Noch keine Repositories';
  @override
  String get emptyText =>
      'Ein Repository ist ein Git-Branch, den Repolupe spiegelt und synchron hält. Sobald es synchronisiert ist, kannst du in Chats Fragen dazu stellen, und das Modell liest seine Dateien, um sie zu beantworten.';
  @override
  String get noMatch => 'Keine Repositories passen zu deiner Suche.';
  @override
  String get added => 'Repository hinzugefügt, wird synchronisiert…';
  @override
  String loadFailed({required Object error}) => 'Die Repositories konnten nicht geladen werden: ${error}';
  @override
  String createFailed({required Object error}) => 'Das Repository konnte nicht hinzugefügt werden: ${error}';
}

// Path: base.repositories.page
class _Translations$base$repositories$page$de extends Translations$base$repositories$page$en {
  _Translations$base$repositories$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get ownerIntro =>
      'Hier kannst du die Details des Repositorys bearbeiten, Synchronisierungen starten und das Repository mit anderen Benutzern teilen.';
  @override
  String get ownerIntroLocal => 'Hier kannst du die Details des Repositorys bearbeiten und das Repository mit anderen Benutzern teilen.';
  @override
  String get sharedIntro => 'Dieses Repository wurde mit dir geteilt. Hier siehst du seine Details und den Stand der Synchronisierung.';
  @override
  String get owner => 'Besitzer';
  @override
  String get ownerYou => 'Du';
  @override
  String get ownerShared => 'Mit dir geteilt';
  @override
  String sizeSplit({required Object git, required Object lfs}) => 'Git ${git}, LFS ${lfs}';
  @override
  String sizeTitle({required Object branch}) => 'Nur der Branch ${branch} wird abgerufen, das Remote kann also größer sein';
  @override
  String get created => 'Erstellt';
  @override
  String get askQuestion => 'Frage stellen';
  @override
  String get lastSyncFailed => 'Letzte Synchronisierung fehlgeschlagen';
  @override
  String get remoteNone => 'Keins (lokales Repository auf diesem Server)';
  @override
  String get tokenNone => 'Keiner (öffentlich)';
  @override
  String get tokenSet => 'Gesetzt';
  @override
  String get writeAccess => 'Schreibzugriff';
  @override
  String get writeAccessEnabled => 'Aktiviert (das Modell kann Änderungen vorschlagen)';
  @override
  String get writeAccessDisabled => 'Deaktiviert (das Modell kann Dateien nur lesen)';
  @override
  String get leave => 'Verlassen';
  @override
  String get sync => 'Synchronisierung';
  @override
  String get interval => 'Intervall';
  @override
  String get intervalLocal => 'Nach jedem Commit';
  @override
  String get headCommit => 'Aktuelle Version';
  @override
  String get lastSynced => 'Zuletzt synchronisiert';
  @override
  String get syncStarted => 'Synchronisierung gestartet';
  @override
  String get nextSync => 'Nächste Synchronisierung';
  @override
  String get syncNow => 'Jetzt synchronisieren';
  @override
  String get deleteTitle => 'Repository löschen';
  @override
  String get deleteText =>
      'Nur die Kopie des Repositorys auf diesem Server wird gelöscht. Das Remote-Repository ist davon nicht betroffen. Chats und Benutzer, mit denen es geteilt ist, verlieren den Zugriff darauf.';
  @override
  String get deleteTextLocal =>
      'Das Repository existiert nur auf diesem Server, daher werden seine Dateien und sein Verlauf endgültig gelöscht. Chats und Benutzer, mit denen es geteilt ist, verlieren den Zugriff darauf.';
  @override
  String get leaveTitle => 'Repository verlassen';
  @override
  String get leaveText =>
      'Du verlierst den Zugriff auf dieses Repository, und es wird aus deinen Chats entfernt. Der Besitzer kann es erneut mit dir teilen.';
  @override
  String get notFound => 'Repository nicht gefunden';
  @override
  String get syncRequested => 'Synchronisierung angefordert.';
  @override
  String get updated => 'Repository aktualisiert.';
  @override
  String get deleted => 'Repository gelöscht.';
  @override
  String get left => 'Du hast das Repository verlassen.';
  @override
  String loadFailed({required Object error}) => 'Das Repository konnte nicht geladen werden: ${error}';
  @override
  String syncFailed({required Object error}) => 'Die Synchronisierung konnte nicht angefordert werden: ${error}';
  @override
  String saveFailed({required Object error}) => 'Das Repository konnte nicht gespeichert werden: ${error}';
  @override
  String deleteFailed({required Object error}) => 'Das Repository konnte nicht gelöscht werden: ${error}';
  @override
  String leaveFailed({required Object error}) => 'Das Repository konnte nicht verlassen werden: ${error}';
}

// Path: base.repositories.kindDialog
class _Translations$base$repositories$kindDialog$de extends Translations$base$repositories$kindDialog$en {
  _Translations$base$repositories$kindDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get remoteDescription => 'Spiegelt einen Branch eines Git-Repositorys, z. B. auf GitHub, GitLab oder Forgejo, und hält ihn synchron.';
  @override
  String get localDescription => 'Erstellt ein leeres Repository, das nur auf diesem Server existiert.';
}

// Path: base.repositories.createDialog
class _Translations$base$repositories$createDialog$de extends Translations$base$repositories$createDialog$en {
  _Translations$base$repositories$createDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get titleRemote => 'Neues Remote-Repository';
  @override
  String get titleLocal => 'Neues lokales Repository';
  @override
  String get descriptionOptional => 'Beschreibung (optional)';
  @override
  String get descriptionHint => 'Hilft dem Modell zu entscheiden, wann es in dieses Repository schauen soll.';
  @override
  String get tokenOptional => 'Zugriffstoken (optional)';
  @override
  String get tokenHint => 'Für private Repositories nötig.';
  @override
  String get allowCommitsHintLocal => 'Ohne Schreibzugriff kann das Modell keine Dateien hinzufügen, das Repository bleibt also leer.';
  @override
  String get remoteUrlHintAdmin => 'Als Admin kannst du auch http:// und interne Hosts verwenden.';
  @override
  String get remoteUrlHintUser => 'Muss https:// und einen Host mit öffentlicher Adresse verwenden.';
  @override
  String get checkingRemote => 'Das Remote wird geprüft, das kann einige Sekunden dauern…';
}

// Path: base.repositories.editDialog
class _Translations$base$repositories$editDialog$de extends Translations$base$repositories$editDialog$en {
  _Translations$base$repositories$editDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Repository bearbeiten';
  @override
  String get keepToken => 'Aktuellen Token behalten';
  @override
  String keepTokenWithHint({required Object hint}) => 'Aktuellen Token behalten (•••• ${hint})';
  @override
  String get removeToken => 'Token entfernen (öffentliches Repository)';
  @override
  String get noToken => 'Kein Token (öffentliches Repository)';
  @override
  String get setToken => 'Neuen Token setzen';
  @override
  String get newToken => 'Neuer Zugriffstoken';
  @override
  String get newTokenHint => 'Ein Token mit Lesezugriff, z. B. ein persönlicher Zugriffstoken.';
  @override
  String get hostChanged =>
      'Das Remote liegt jetzt auf einem anderen Host, daher kann der aktuelle Token nicht behalten werden. Setze einen neuen Token oder entferne ihn, wenn das neue Remote öffentlich ist.';
  @override
  String get missingToken => 'Token fehlt';
}

// Path: base.repositories.usersCard
class _Translations$base$repositories$usersCard$de extends Translations$base$repositories$usersCard$en {
  _Translations$base$repositories$usersCard$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Teilen';
  @override
  String get description =>
      'Benutzer, mit denen es geteilt ist, können dieses Repository lesen und in ihren Chats verwenden, es aber nicht ändern, synchronisieren oder löschen. Ist der Schreibzugriff aktiviert, kannst du ihnen erlauben, die vom Modell vorgeschlagenen Änderungen mit dem Zugriffstoken dieses Repositorys zu übernehmen.';
  @override
  String get descriptionLocal =>
      'Benutzer, mit denen es geteilt ist, können dieses Repository lesen und in ihren Chats verwenden, es aber nicht ändern oder löschen. Ist der Schreibzugriff aktiviert, kannst du ihnen erlauben, die vom Modell vorgeschlagenen Änderungen zu übernehmen.';
  @override
  String get notShared => 'Mit niemandem geteilt';
  @override
  String get user => 'Benutzer';
  @override
  String get sharedAt => 'Geteilt';
  @override
  String get canCommit => 'Schreibzugriff';
  @override
  String get canCommitOff => 'Aktiviere zuerst den Schreibzugriff für das Repository';
  @override
  String get stopSharing => 'Nicht mehr teilen';
  @override
  String get stopSharingTitle => 'Nicht mehr teilen';
  @override
  String stopSharingText({required Object name}) => '${name} verliert den Zugriff auf dieses Repository, und es wird aus den eigenen Chats entfernt.';
  @override
  String get shared => 'Repository geteilt.';
  @override
  String get unknownUser => 'Kein Benutzer mit diesem Benutzernamen oder dieser E-Mail';
  @override
  String get stopped => 'Nicht mehr geteilt.';
  @override
  String loadFailed({required Object error}) => 'Die Benutzer konnten nicht geladen werden: ${error}';
  @override
  String shareFailed({required Object error}) => 'Das Repository konnte nicht geteilt werden: ${error}';
  @override
  String canCommitFailed({required Object error}) => 'Der Schreibzugriff konnte nicht geändert werden: ${error}';
  @override
  String stopFailed({required Object error}) => 'Das Teilen konnte nicht beendet werden: ${error}';
}

// Path: base.repositories.shareDialog
class _Translations$base$repositories$shareDialog$de extends Translations$base$repositories$shareDialog$en {
  _Translations$base$repositories$shareDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Repository teilen';
  @override
  String get description =>
      'Der Benutzer kann dieses Repository lesen und in seinen Chats verwenden, es aber nicht ändern, synchronisieren oder löschen.';
  @override
  String get missing => 'Benutzername oder E-Mail fehlt';
}

// Path: base.documents.card
class _Translations$base$documents$card$de extends Translations$base$documents$card$en {
  _Translations$base$documents$card$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String paused({required Object time}) => 'Der OCR-Dienst ist nicht verfügbar. Die Umwandlungen sind bis ${time} pausiert.';
}

// Path: base.documents.statusFilter
class _Translations$base$documents$statusFilter$de extends Translations$base$documents$statusFilter$en {
  _Translations$base$documents$statusFilter$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get filterByStatus => 'Nach Status filtern';
  @override
  String get all => 'Alle';
}

// Path: base.documents.details
class _Translations$base$documents$details$de extends Translations$base$documents$details$en {
  _Translations$base$documents$details$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String started({required Object relative}) => 'Gestartet ${relative}';
  @override
  String skipped({required Object reason, required Object relative}) => '${reason} Neuer Versuch ${relative}.';
  @override
  String get lfsObjectMissing => 'Die Datei ist mit Git LFS gespeichert und konnte nicht heruntergeladen werden.';
  @override
  String get unreadable => 'Die Datei konnte nicht gelesen werden.';
  @override
  String get settingsChanged => 'Geänderte Einstellungen';
  @override
  String get kNew => 'Neu';
}

// Path: base.admin.users
class _Translations$base$admin$users$de extends Translations$base$admin$users$en {
  _Translations$base$admin$users$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Benutzer';
  @override
  String get mustChangePassword => 'Muss Passwort ändern';
  @override
  String get chooseOwnPasswordHint => 'Der Benutzer wählt nach der Anmeldung mit diesem Passwort ein eigenes';
  @override
  late final _Translations$base$admin$users$page$de page = _Translations$base$admin$users$page$de._(_root);
  @override
  late final _Translations$base$admin$users$createDialog$de createDialog = _Translations$base$admin$users$createDialog$de._(_root);
  @override
  late final _Translations$base$admin$users$editDialog$de editDialog = _Translations$base$admin$users$editDialog$de._(_root);
  @override
  late final _Translations$base$admin$users$passwordDialog$de passwordDialog = _Translations$base$admin$users$passwordDialog$de._(_root);
  @override
  late final _Translations$base$admin$users$deleteDialog$de deleteDialog = _Translations$base$admin$users$deleteDialog$de._(_root);
}

// Path: base.admin.llm
class _Translations$base$admin$llm$de extends Translations$base$admin$llm$en {
  _Translations$base$admin$llm$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'LLM-Anbieter';
  @override
  String get newProvider => 'Neuer Anbieter';
  @override
  String get pricePerMillion => 'Preis pro 1 Mio. Tokens';
  @override
  late final _Translations$base$admin$llm$page$de page = _Translations$base$admin$llm$page$de._(_root);
  @override
  late final _Translations$base$admin$llm$providerDialog$de providerDialog = _Translations$base$admin$llm$providerDialog$de._(_root);
  @override
  late final _Translations$base$admin$llm$modelDialog$de modelDialog = _Translations$base$admin$llm$modelDialog$de._(_root);
  @override
  late final _Translations$base$admin$llm$remoteModelsDialog$de remoteModelsDialog = _Translations$base$admin$llm$remoteModelsDialog$de._(_root);
}

// Path: base.admin.config
class _Translations$base$admin$config$de extends Translations$base$admin$config$en {
  _Translations$base$admin$config$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Konfiguration';
  @override
  String get overrideAction => 'Überschreiben';
  @override
  late final _Translations$base$admin$config$page$de page = _Translations$base$admin$config$page$de._(_root);
  @override
  late final _Translations$base$admin$config$overrideDialog$de overrideDialog = _Translations$base$admin$config$overrideDialog$de._(_root);
}

// Path: base.admin.extraction
class _Translations$base$admin$extraction$de extends Translations$base$admin$extraction$en {
  _Translations$base$admin$extraction$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dokumentextraktion';
  @override
  late final _Translations$base$admin$extraction$page$de page = _Translations$base$admin$extraction$page$de._(_root);
}

// Path: flutter.common.unsavedChanges
class _Translations$flutter$common$unsavedChanges$de extends Translations$flutter$common$unsavedChanges$en {
  _Translations$flutter$common$unsavedChanges$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Änderungen verwerfen?';
  @override
  String get text => 'Deine Änderungen wurden nicht gespeichert.';
  @override
  String get keepEditing => 'Weiter bearbeiten';
  @override
  String get discard => 'Verwerfen';
}

// Path: flutter.chat.page
class _Translations$flutter$chat$page$de extends Translations$flutter$chat$page$en {
  _Translations$flutter$chat$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get temporaryOff => 'Temporären Chat ausschalten';
}

// Path: flutter.chat.markdownContent
class _Translations$flutter$chat$markdownContent$de extends Translations$flutter$chat$markdownContent$en {
  _Translations$flutter$chat$markdownContent$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String openLinkFailed({required Object link}) => '${link} konnte nicht geöffnet werden';
}

// Path: flutter.chat.repositorySheet
class _Translations$flutter$chat$repositorySheet$de extends Translations$flutter$chat$repositorySheet$en {
  _Translations$flutter$chat$repositorySheet$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get fixedHint => 'Ein Chat behält die Repositories, mit denen er gestartet wurde.';
  @override
  String get unavailable => 'Nicht verfügbares Repository';
}

// Path: flutter.chat.toolCallPage
class _Translations$flutter$chat$toolCallPage$de extends Translations$flutter$chat$toolCallPage$en {
  _Translations$flutter$chat$toolCallPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String commit({required Object sha}) => 'Commit ${sha}';
}

// Path: flutter.chat.presentedFilePage
class _Translations$flutter$chat$presentedFilePage$de extends Translations$flutter$chat$presentedFilePage$en {
  _Translations$flutter$chat$presentedFilePage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get cannotShow => 'Diese Datei kann in der App nicht angezeigt werden.';
}

// Path: flutter.chat.proposedCommitPage
class _Translations$flutter$chat$proposedCommitPage$de extends Translations$flutter$chat$proposedCommitPage$en {
  _Translations$flutter$chat$proposedCommitPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get notApplied => 'Noch nicht übernommen.';
}

// Path: flutter.settings.changePasswordPage
class _Translations$flutter$settings$changePasswordPage$de extends Translations$flutter$settings$changePasswordPage$en {
  _Translations$flutter$settings$changePasswordPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get intro => 'Du musst dein Passwort ändern, bevor du fortfahren kannst.';
}

// Path: flutter.settings.accountSheet
class _Translations$flutter$settings$accountSheet$de extends Translations$flutter$settings$accountSheet$en {
  _Translations$flutter$settings$accountSheet$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get accounts => 'Konten';
  @override
  String get addAccount => 'Konto hinzufügen';
}

// Path: flutter.settings.preferences
class _Translations$flutter$settings$preferences$de extends Translations$flutter$settings$preferences$en {
  _Translations$flutter$settings$preferences$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get deviceDefault => 'Standard des Geräts';
  @override
  String deviceDefaultWithLocale({required Object locale}) => 'Standard des Geräts (${locale})';
  @override
  late final _Translations$flutter$settings$preferences$modelSheet$de modelSheet = _Translations$flutter$settings$preferences$modelSheet$de._(_root);
}

// Path: flutter.repositories.listPage
class _Translations$flutter$repositories$listPage$de extends Translations$flutter$repositories$listPage$en {
  _Translations$flutter$repositories$listPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get addedLocal => 'Repository hinzugefügt.';
}

// Path: flutter.repositories.page
class _Translations$flutter$repositories$page$de extends Translations$flutter$repositories$page$en {
  _Translations$flutter$repositories$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String tokenSetWithHint({required Object hint}) => 'Gesetzt (•••• ${hint})';
}

// Path: flutter.repositories.form
class _Translations$flutter$repositories$form$de extends Translations$flutter$repositories$form$en {
  _Translations$flutter$repositories$form$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get showToken => 'Token anzeigen';
  @override
  String get hideToken => 'Token ausblenden';
}

// Path: flutter.repositories.usersCard
class _Translations$flutter$repositories$usersCard$de extends Translations$flutter$repositories$usersCard$en {
  _Translations$flutter$repositories$usersCard$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String sharedRelative({required Object relative}) => 'Geteilt ${relative}';
  @override
  String get canCommitOn => 'Darf die vom Modell vorgeschlagenen Änderungen übernehmen';
}

// Path: flutter.documents.details
class _Translations$flutter$documents$details$de extends Translations$flutter$documents$details$en {
  _Translations$flutter$documents$details$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get path => 'Pfad';
  @override
  String get started => 'Gestartet';
  @override
  String get reason => 'Grund';
  @override
  String get triedAgain => 'Neuer Versuch';
  @override
  String get settingsChanged => 'Geänderte Einstellungen: Das Dokument wird mit den aktuellen Einstellungen erneut umgewandelt.';
  @override
  String get newDocument => 'Neu: Das Dokument wurde noch nicht umgewandelt.';
  @override
  String get convertedEarlier => 'Umgewandelt (frühere Einstellungen)';
  @override
  String failedRelative({required Object relative}) => 'Fehlgeschlagen ${relative}';
  @override
  String get ocrUsed => 'Seiten wurden per OCR erkannt, der Text kann also Fehler enthalten.';
  @override
  String get ocrNotUsed => 'Nein';
}

// Path: flutter.format.relative
class _Translations$flutter$format$relative$de extends Translations$flutter$format$relative$en {
  _Translations$flutter$format$relative$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get justNow => 'gerade eben';
  @override
  String minutesAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'vor 1 Minute',
    other: 'vor ${count} Minuten',
  );
  @override
  String inMinutes({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'in 1 Minute',
    other: 'in ${count} Minuten',
  );
  @override
  String hoursAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'vor 1 Stunde',
    other: 'vor ${count} Stunden',
  );
  @override
  String inHours({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'in 1 Stunde',
    other: 'in ${count} Stunden',
  );
  @override
  String daysAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'vor 1 Tag',
    other: 'vor ${count} Tagen',
  );
  @override
  String inDays({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'in 1 Tag',
    other: 'in ${count} Tagen',
  );
}

// Path: flutter.admin.users
class _Translations$flutter$admin$users$de extends Translations$flutter$admin$users$en {
  _Translations$flutter$admin$users$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get showPassword => 'Passwort anzeigen';
  @override
  String get hidePassword => 'Passwort verbergen';
  @override
  late final _Translations$flutter$admin$users$page$de page = _Translations$flutter$admin$users$page$de._(_root);
  @override
  late final _Translations$flutter$admin$users$userPage$de userPage = _Translations$flutter$admin$users$userPage$de._(_root);
  @override
  late final _Translations$flutter$admin$users$form$de form = _Translations$flutter$admin$users$form$de._(_root);
  @override
  late final _Translations$flutter$admin$users$flags$de flags = _Translations$flutter$admin$users$flags$de._(_root);
}

// Path: flutter.admin.llm
class _Translations$flutter$admin$llm$de extends Translations$flutter$admin$llm$en {
  _Translations$flutter$admin$llm$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$llm$page$de page = _Translations$flutter$admin$llm$page$de._(_root);
  @override
  late final _Translations$flutter$admin$llm$providerForm$de providerForm = _Translations$flutter$admin$llm$providerForm$de._(_root);
  @override
  late final _Translations$flutter$admin$llm$modelForm$de modelForm = _Translations$flutter$admin$llm$modelForm$de._(_root);
}

// Path: flutter.admin.config
class _Translations$flutter$admin$config$de extends Translations$flutter$admin$config$en {
  _Translations$flutter$admin$config$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$config$page$de page = _Translations$flutter$admin$config$page$de._(_root);
  @override
  late final _Translations$flutter$admin$config$overrideDialog$de overrideDialog = _Translations$flutter$admin$config$overrideDialog$de._(_root);
}

// Path: flutter.admin.extraction
class _Translations$flutter$admin$extraction$de extends Translations$flutter$admin$extraction$en {
  _Translations$flutter$admin$extraction$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$extraction$page$de page = _Translations$flutter$admin$extraction$page$de._(_root);
}

// Path: base.settings.account.page
class _Translations$base$settings$account$page$de extends Translations$base$settings$account$page$en {
  _Translations$base$settings$account$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get memberSince => 'Mitglied seit';
  @override
  String get identitySaved => 'Benutzername und E-Mail gespeichert';
  @override
  String get passwordChanged => 'Passwort geändert. Deine anderen Sitzungen wurden abgemeldet.';
  @override
  String identitySaveFailed({required Object error}) => 'Benutzername und E-Mail konnten nicht gespeichert werden: ${error}';
  @override
  String changePasswordFailed({required Object error}) => 'Das Passwort konnte nicht geändert werden: ${error}';
}

// Path: base.settings.account.changePasswordDialog
class _Translations$base$settings$account$changePasswordDialog$de extends Translations$base$settings$account$changePasswordDialog$en {
  _Translations$base$settings$account$changePasswordDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Passwort ändern';
  @override
  String get signOutNote => 'Alle deine anderen Sitzungen werden abgemeldet.';
  @override
  String get fillAll => 'Bitte fülle alle Felder aus.';
}

// Path: base.settings.account.identityDialog
class _Translations$base$settings$account$identityDialog$de extends Translations$base$settings$account$identityDialog$en {
  _Translations$base$settings$account$identityDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Benutzername und E-Mail ändern';
  @override
  String get loginHint => 'Du kannst dich mit beidem anmelden.';
}

// Path: base.settings.profile.page
class _Translations$base$settings$profile$page$de extends Translations$base$settings$profile$page$en {
  _Translations$base$settings$profile$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get description => 'Was der Assistent über dich erfährt, damit er weiß, wer „ich“ in deinen Fragen ist.';
  @override
  String get updated => 'Profil aktualisiert.';
  @override
  String saveFailed({required Object error}) => 'Das Profil konnte nicht gespeichert werden: ${error}';
}

// Path: base.settings.profile.dialog
class _Translations$base$settings$profile$dialog$de extends Translations$base$settings$profile$dialog$en {
  _Translations$base$settings$profile$dialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Profil bearbeiten';
  @override
  String get description => 'Das erfährt der Assistent über dich, damit er weiß, wer „ich“ in deinen Fragen ist.';
  @override
  String get fullNameHint => 'So wie er in Dokumenten steht';
  @override
  String get aboutPlaceholder => 'Z. B. deine Rolle, die Projekte, an denen du arbeitest, oder wie dir Antworten am liebsten sind.';
  @override
  String fullNameTooLong({required Object max}) => 'Der vollständige Name darf höchstens ${max} Zeichen lang sein.';
  @override
  String firstNameTooLong({required Object max}) => 'Der Vorname darf höchstens ${max} Zeichen lang sein.';
  @override
  String aboutTooLong({required Object max}) => '„Über dich“ darf höchstens ${max} Zeichen lang sein.';
}

// Path: base.settings.preferences.page
class _Translations$base$settings$preferences$page$de extends Translations$base$settings$preferences$page$en {
  _Translations$base$settings$preferences$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get noModels => 'Keine Modelle konfiguriert';
  @override
  String get noModelsAskAdmin => 'Keine Modelle konfiguriert. Bitte einen Admin, eines hinzuzufügen.';
  @override
  String get modelUpdated => 'Modell aktualisiert.';
  @override
  String get languageUpdated => 'Sprache aktualisiert.';
  @override
  String get autoCommit => 'Änderungen automatisch übernehmen';
  @override
  String get autoCommitHint => 'Änderungen, die der Assistent vorschlägt, werden übernommen, sobald seine Antwort fertig ist.';
  @override
  String get autoCommitOn => 'Vorgeschlagene Änderungen werden jetzt automatisch übernommen.';
  @override
  String get autoCommitOff => 'Vorgeschlagene Änderungen warten jetzt darauf, dass du sie übernimmst.';
  @override
  String modelsLoadFailed({required Object error}) => 'Die Modelle konnten nicht geladen werden: ${error}';
  @override
  String modelSaveFailed({required Object error}) => 'Das Modell konnte nicht gespeichert werden: ${error}';
  @override
  String languageSaveFailed({required Object error}) => 'Die Sprache konnte nicht gespeichert werden: ${error}';
  @override
  String autoCommitSaveFailed({required Object error}) => 'Die Einstellung konnte nicht gespeichert werden: ${error}';
}

// Path: base.settings.preferences.localeDialog
class _Translations$base$settings$preferences$localeDialog$de extends Translations$base$settings$preferences$localeDialog$en {
  _Translations$base$settings$preferences$localeDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Sprache bearbeiten';
  @override
  String get description => 'Die Sprache, in der das Modell antwortet, und auch die Sprache der Oberfläche, sofern sie darin verfügbar ist.';
  @override
  String get label => 'Sprache (BCP-47)';
}

// Path: base.settings.preferences.modelDialog
class _Translations$base$settings$preferences$modelDialog$de extends Translations$base$settings$preferences$modelDialog$en {
  _Translations$base$settings$preferences$modelDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Modell bearbeiten';
  @override
  String get description => 'Das Modell, das deine Fragen beantwortet.';
}

// Path: base.admin.users.page
class _Translations$base$admin$users$page$de extends Translations$base$admin$users$page$en {
  _Translations$base$admin$users$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    zero: '${count} Benutzer',
    one: '${count} Benutzer',
    other: '${count} Benutzer',
  );
  @override
  String get description =>
      'Jeder Benutzer hat eigene Chats und, falls erlaubt, eigene Repositories. LLM-Anbieter und Modelle werden von Admins eingerichtet und von allen genutzt.';
  @override
  String get newUser => 'Neuer Benutzer';
  @override
  String get user => 'Benutzer';
  @override
  String get identity => 'Identität';
  @override
  String get noUsers => 'Keine Benutzer';
  @override
  String get loginDisabled => 'Anmeldung deaktiviert';
  @override
  String get passwordChangeRequired => 'Passwortänderung erforderlich';
  @override
  String get manage => 'Verwalten';
  @override
  String get readOnly => 'Nur lesen';
  @override
  String get editable => 'Änderbar';
  @override
  String get fixed => 'Fest';
  @override
  String get cannotDeleteSelf => 'Du kannst dich nicht selbst löschen';
  @override
  String get cannotDeleteAdmin => 'Admins können nicht gelöscht werden';
  @override
  String get setPassword => 'Passwort festlegen';
  @override
  String get cannotSetOwnPassword => 'Ändere dein eigenes Passwort in deinen Kontoeinstellungen';
  @override
  String get created => 'Benutzer erstellt.';
  @override
  String get updated => 'Benutzer aktualisiert.';
  @override
  String get passwordSet => 'Passwort festgelegt.';
  @override
  String get deleted => 'Benutzer gelöscht.';
  @override
  String loadFailed({required Object error}) => 'Die Benutzer konnten nicht geladen werden: ${error}';
  @override
  String createFailed({required Object error}) => 'Der Benutzer konnte nicht erstellt werden: ${error}';
  @override
  String saveFailed({required Object error}) => 'Der Benutzer konnte nicht gespeichert werden: ${error}';
  @override
  String setPasswordFailed({required Object error}) => 'Das Passwort konnte nicht festgelegt werden: ${error}';
  @override
  String deleteFailed({required Object error}) => 'Der Benutzer konnte nicht gelöscht werden: ${error}';
}

// Path: base.admin.users.createDialog
class _Translations$base$admin$users$createDialog$de extends Translations$base$admin$users$createDialog$en {
  _Translations$base$admin$users$createDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Benutzer erstellen';
}

// Path: base.admin.users.editDialog
class _Translations$base$admin$users$editDialog$de extends Translations$base$admin$users$editDialog$en {
  _Translations$base$admin$users$editDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Benutzer bearbeiten';
  @override
  String get adminUnrestricted => 'Admins können nicht eingeschränkt werden';
  @override
  String get canLogin => 'Darf sich anmelden';
  @override
  String get canLoginHint => 'Beim Ausschalten wird der Benutzer überall abgemeldet';
  @override
  String get canManageRepositories => 'Darf Repositories verwalten';
  @override
  String get canManageRepositoriesHint =>
      'Ohne diese Berechtigung ist die Seite Repositories ausgeblendet, und der Benutzer kann nur Fragen zu Repositories stellen, die mit ihm geteilt wurden';
  @override
  String get canChangeIdentity => 'Darf Benutzername und E-Mail ändern';
  @override
  String get canChangeIdentityHint => 'Ohne diese Berechtigung können nur Admins sie ändern';
  @override
  String get mustChangePasswordHint => 'Bis dahin kann der Benutzer nach der Anmeldung nichts anderes tun';
}

// Path: base.admin.users.passwordDialog
class _Translations$base$admin$users$passwordDialog$de extends Translations$base$admin$users$passwordDialog$en {
  _Translations$base$admin$users$passwordDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Passwort festlegen';
  @override
  String intro({required Object name}) => 'Legt ein neues Passwort für ${name} fest und meldet den Benutzer überall ab.';
}

// Path: base.admin.users.deleteDialog
class _Translations$base$admin$users$deleteDialog$de extends Translations$base$admin$users$deleteDialog$en {
  _Translations$base$admin$users$deleteDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Benutzer löschen';
  @override
  String get intro => 'Dieser Benutzer wird gelöscht:';
  @override
  String get consequences =>
      'Seine Sitzungen, Chats und Repositories werden ebenfalls gelöscht. Repositories, die ihm gehören, werden auch für alle entfernt, mit denen sie geteilt wurden.';
}

// Path: base.admin.llm.page
class _Translations$base$admin$llm$page$de extends Translations$base$admin$llm$page$en {
  _Translations$base$admin$llm$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    zero: '${count} Modelle',
    one: '${count} Modell',
    other: '${count} Modelle',
  );
  @override
  String get providerIntro =>
      'Ein Anbieter ist ein LLM-Server: die Anthropic-API oder ein beliebiger OpenAI-kompatibler Server wie OpenRouter, Ollama, vLLM oder LM Studio.';
  @override
  String get modelsIntro => 'Modelle gehören zu einem Anbieter und müssen Streaming und Tool-Aufrufe unterstützen.';
  @override
  String defaultIntro({required Object icon}) => 'Das Standardmodell (${icon}) antwortet Benutzern, die in ihren Einstellungen keines gewählt haben.';
  @override
  String get emptyTitle => 'Noch keine Anbieter';
  @override
  String get emptyText =>
      'Niemand kann Fragen stellen, bis ein Modell eingerichtet ist. Das erste Modell, das du hinzufügst, wird zum Standardmodell.';
  @override
  String get noModels => 'Füge einem Anbieter ein Modell hinzu. Bis dahin kann niemand Fragen stellen.';
  @override
  String noDefault({required Object icon}) =>
      'Es gibt kein Standardmodell. Benutzer, die in ihren Einstellungen kein Modell gewählt haben, können keine Fragen stellen, bis du eines zum Standard machst (${icon}).';
  @override
  String get editProvider => 'Anbieter bearbeiten';
  @override
  String get deleteProvider => 'Anbieter löschen';
  @override
  String get defaultModel => 'Standardmodell';
  @override
  String get makeDefault => 'Zum Standard machen';
  @override
  String price({required Object input, required Object output}) => '${input} Eingabe / ${output} Ausgabe';
  @override
  String cachePrices({required Object read, required Object write}) => 'Cache lesen ${read}, Cache schreiben ${write}';
  @override
  String get notSet => 'Nicht festgelegt';
  @override
  String get editModel => 'Modell bearbeiten';
  @override
  String get deleteModel => 'Modell löschen';
  @override
  String get noModelsYet => 'Noch keine Modelle.';
  @override
  String get fetchModels => 'Modelle abrufen';
  @override
  String get addModel => 'Modell hinzufügen';
  @override
  String get deleteProviderTitle => 'Anbieter löschen';
  @override
  String deleteProviderText({required num count, required Object name}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'Der Anbieter ${name} wird zusammen mit seinem Modell gelöscht. Benutzer, die es gewählt haben, verwenden stattdessen das Standardmodell.',
    other:
        'Der Anbieter ${name} wird zusammen mit seinen ${count} Modellen gelöscht. Benutzer, die eines davon gewählt haben, verwenden stattdessen das Standardmodell.',
  );
  @override
  String get deleteProviderHasDefault => 'Er hat das Standardmodell, danach gibt es also kein Standardmodell mehr.';
  @override
  String get deleteModelTitle => 'Modell löschen';
  @override
  String deleteModelText({required Object name}) =>
      'Das Modell ${name} wird gelöscht. Benutzer, die es gewählt haben, verwenden stattdessen das Standardmodell.';
  @override
  String get deleteModelIsDefault => 'Es ist das Standardmodell, danach gibt es also kein Standardmodell mehr.';
  @override
  String get kContinue => 'Fortfahren?';
  @override
  String get providerUpdated => 'Anbieter aktualisiert.';
  @override
  String get providerCreated => 'Anbieter erstellt.';
  @override
  String get providerDeleted => 'Anbieter gelöscht.';
  @override
  String get modelUpdated => 'Modell aktualisiert.';
  @override
  String modelsAdded({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: 'Modell hinzugefügt.',
    other: '${count} Modelle hinzugefügt.',
  );
  @override
  String get modelDeleted => 'Modell gelöscht.';
  @override
  String partlyAdded({required Object added, required Object total, required Object error}) => '${added} von ${total} Modellen hinzugefügt. ${error}';
  @override
  String partlyAddedMore({required Object added, required Object total, required Object error, required Object more}) =>
      '${added} von ${total} Modellen hinzugefügt. ${error} (und ${more} weitere)';
  @override
  String get defaultChanged => 'Standardmodell geändert.';
  @override
  String loadFailed({required Object error}) => 'Die Anbieter konnten nicht geladen werden: ${error}';
  @override
  String createProviderFailed({required Object error}) => 'Der Anbieter konnte nicht erstellt werden: ${error}';
  @override
  String saveProviderFailed({required Object error}) => 'Der Anbieter konnte nicht gespeichert werden: ${error}';
  @override
  String deleteProviderFailed({required Object error}) => 'Der Anbieter konnte nicht gelöscht werden: ${error}';
  @override
  String addModelFailed({required Object error}) => 'Das Modell konnte nicht hinzugefügt werden: ${error}';
  @override
  String saveModelFailed({required Object error}) => 'Das Modell konnte nicht gespeichert werden: ${error}';
  @override
  String deleteModelFailed({required Object error}) => 'Das Modell konnte nicht gelöscht werden: ${error}';
  @override
  String setDefaultFailed({required Object error}) => 'Das Standardmodell konnte nicht geändert werden: ${error}';
}

// Path: base.admin.llm.providerDialog
class _Translations$base$admin$llm$providerDialog$de extends Translations$base$admin$llm$providerDialog$en {
  _Translations$base$admin$llm$providerDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get editTitle => 'Anbieter bearbeiten';
  @override
  String get apiFormat => 'API-Format';
  @override
  String get currency => 'Währung';
  @override
  String get baseUrl => 'Basis-URL';
  @override
  String get apiKey => 'API-Schlüssel';
  @override
  String currentKey({required Object key}) => '(aktuell ${key})';
  @override
  String get keyNone => 'keiner';
  @override
  String get keySet => 'gesetzt';
  @override
  String get keepKey => 'Aktuellen Schlüssel behalten';
  @override
  String get removeKey => 'Schlüssel entfernen';
  @override
  String get noKey => 'Kein Schlüssel';
  @override
  String get setKey => 'Neuen Schlüssel setzen';
  @override
  String get newKey => 'Neuer API-Schlüssel';
  @override
  String get hostChanged =>
      'Die Basis-URL zeigt jetzt auf einen anderen Host, daher kann der aktuelle Schlüssel nicht behalten werden. Setze einen neuen Schlüssel oder entferne ihn, wenn der neue Server keinen braucht.';
  @override
  String get thirdParty => 'Server von Drittanbietern';
  @override
  String nameLength({required Object max}) => '1 bis ${max} Zeichen.';
  @override
  String get missingApiKey => 'API-Schlüssel fehlt';
}

// Path: base.admin.llm.modelDialog
class _Translations$base$admin$llm$modelDialog$de extends Translations$base$admin$llm$modelDialog$en {
  _Translations$base$admin$llm$modelDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get editTitle => 'Modell bearbeiten';
  @override
  String newTitle({required Object provider}) => 'Neues Modell für ${provider}';
  @override
  String get apiName => 'API-Name';
  @override
  String get displayName => 'Anzeigename';
  @override
  String get maxOutputTokens => 'Max. Ausgabe-Tokens';
  @override
  String get noCurrency =>
      'Der Anbieter hat keine Währung, daher haben seine Modelle keine Preise. Lege eine für den Anbieter fest, um sie einzugeben.';
  @override
  String get priceHint => 'Zeigt die Kosten jeder Antwort an. Lass Eingabe und Ausgabe leer, um keine anzuzeigen.';
  @override
  String get cacheRead => 'Cache lesen';
  @override
  String get cacheWrite => 'Cache schreiben';
  @override
  String get sameAsInput => 'Wie Eingabe';
  @override
  String get becomesDefault => 'Es gibt noch kein Standardmodell, daher wird dieses Modell zum Standard.';
  @override
  String get tokensInvalid => 'Muss eine positive ganze Zahl sein.';
  @override
  String priceInvalid({required Object max, required Object decimals}) => 'Eine Zahl bis ${max} mit höchstens ${decimals} Nachkommastellen.';
  @override
  String get missingApiName => 'API-Name fehlt';
  @override
  String apiNameTooLong({required Object max}) => 'Der API-Name darf höchstens ${max} Zeichen lang sein';
  @override
  String displayNameTooLong({required Object max}) => 'Der Anzeigename darf höchstens ${max} Zeichen lang sein';
  @override
  String get maxOutputTokensInvalid => 'Max. Ausgabe-Tokens müssen eine positive ganze Zahl sein';
  @override
  String pricesInvalid({required Object max, required Object decimals}) =>
      'Preise müssen Zahlen bis ${max} mit höchstens ${decimals} Nachkommastellen sein';
  @override
  String get inputOutputBoth => 'Lege Eingabe- und Ausgabepreis fest oder keinen von beiden';
  @override
  String get cacheRequiresPrices => 'Cache-Preise erfordern Eingabe- und Ausgabepreise';
}

// Path: base.admin.llm.remoteModelsDialog
class _Translations$base$admin$llm$remoteModelsDialog$de extends Translations$base$admin$llm$remoteModelsDialog$en {
  _Translations$base$admin$llm$remoteModelsDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'Modelle von ${name}';
  @override
  String get fetching => 'Der Server wird nach seinen Modellen gefragt…';
  @override
  String get addByNameHint => 'Du kannst die Modelle trotzdem über ihren Namen hinzufügen.';
  @override
  String get noModels => 'Der Server listet keine Modelle auf.';
  @override
  String get intro =>
      'Wähle die Modelle aus, die hinzugefügt werden sollen. Sie müssen Streaming und Tool-Aufrufe unterstützen. Preise und max. Ausgabe-Tokens kannst du danach festlegen, indem du jedes Modell bearbeitest.';
  @override
  String get selectAll => 'Alle auswählen';
  @override
  String selectAllMatches({required Object count}) => 'Alle ${count} Treffer auswählen';
  @override
  String noMatch({required Object query}) => 'Kein Modell passt zu „${query}“.';
  @override
  String get becomesDefault => 'Es gibt noch kein Standardmodell, daher wird das erste hinzugefügte Modell zum Standard.';
  @override
  String get addByName => 'Über Namen hinzufügen';
  @override
  String addModels({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: '1 Modell hinzufügen',
    other: '${count} Modelle hinzufügen',
  );
}

// Path: base.admin.config.page
class _Translations$base$admin$config$page$de extends Translations$base$admin$config$page$en {
  _Translations$base$admin$config$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get stored => 'Überschreibungen werden in der Datenbank gespeichert und bleiben daher auch nach einem Neustart des Servers erhalten.';
  @override
  String recommendEnv({required Object envVars}) =>
      'Wir empfehlen ${envVars}, damit die Einrichtung deklarativ an einer Stelle bleibt. Überschreibungen sind für schnelle Tests gedacht.';
  @override
  String get envVars => 'Umgebungsvariablen';
  @override
  String get ocrHint =>
      'Wenn du die OCR-Einstellungen änderst, werden alle Dokumente nacheinander neu umgewandelt. Bis dahin wird ihr bisheriger Text verwendet.';
  @override
  String get key => 'Schlüssel';
  @override
  String get env => 'Umgebung';
  @override
  String get kOverride => 'Überschreibung';
  @override
  String get noConfig => 'Keine Konfiguration';
  @override
  String get notSet => 'nicht gesetzt';
  @override
  String get envOnly => 'Nur Umgebung';
  @override
  String get useEnv => 'Wert der Umgebungsvariable verwenden';
  @override
  String get updated => 'Konfiguration aktualisiert.';
  @override
  String loadFailed({required Object error}) => 'Die Konfiguration konnte nicht geladen werden: ${error}';
  @override
  String saveFailed({required Object error}) => 'Die Überschreibung konnte nicht gespeichert werden: ${error}';
}

// Path: base.admin.config.overrideDialog
class _Translations$base$admin$config$overrideDialog$de extends Translations$base$admin$config$overrideDialog$en {
  _Translations$base$admin$config$overrideDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String env({required Object value}) => 'Umgebung: ${value}';
  @override
  String get value => 'Wert';
  @override
  String get clearHint => 'Leeren, um den Wert der Umgebungsvariable zu verwenden';
  @override
  String get emptyHint => 'Leer lassen, um den Wert der Umgebungsvariable zu verwenden';
}

// Path: base.admin.extraction.page
class _Translations$base$admin$extraction$page$de extends Translations$base$admin$extraction$page$en {
  _Translations$base$admin$extraction$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(
    count,
    one: '${count} Dokument',
    other: '${count} Dokumente',
  );
  @override
  String ocrSettings({required Object config}) =>
      'Die OCR-Einstellungen sind Teil der ${config}. Wenn du sie änderst, werden alle Dokumente neu umgewandelt.';
  @override
  String get configLink => 'Konfiguration';
  @override
  String get pausedTitle => 'Der OCR-Dienst ist nicht verfügbar';
  @override
  String pausedUntil({required Object time}) => 'Die Umwandlungen sind bis ${time} pausiert.';
  @override
  String get now => 'Jetzt';
  @override
  String converting({required Object path, required Object started}) => '${path} wird umgewandelt, gestartet ${started}';
  @override
  String convertingAttachment({required Object path, required Object started}) =>
      '${path} (an einen Chat angehängt) wird umgewandelt, gestartet ${started}';
  @override
  String convertingRepository({required Object path, required Object repository, required Object owner, required Object started}) =>
      '${path} in ${repository} (${owner}) wird umgewandelt, gestartet ${started}';
  @override
  String get statusPaused => 'Pausiert';
  @override
  String get statusWaiting => 'Wartet auf das nächste Dokument';
  @override
  String get statusIdle => 'Leerlauf, es warten keine Dokumente';
  @override
  String total({required Object count}) => '${count} gesamt';
  @override
  String converted({required Object count}) => '${count} umgewandelt';
  @override
  String failed({required Object count}) => '${count} fehlgeschlagen';
  @override
  String waiting({required Object count}) => '${count} wartend';
  @override
  String notAvailable({required Object count}) => '${count} nicht verfügbar';
  @override
  String get extractor => 'Extraktor';
  @override
  String get convertAgain => 'Erneut umwandeln';
  @override
  String get retried => 'Das Dokument wird neu umgewandelt.';
  @override
  String loadFailed({required Object error}) => 'Die Dokumente konnten nicht geladen werden: ${error}';
  @override
  String retryFailed({required Object error}) => 'Das Dokument konnte nicht neu umgewandelt werden: ${error}';
}

// Path: flutter.settings.preferences.modelSheet
class _Translations$flutter$settings$preferences$modelSheet$de extends Translations$flutter$settings$preferences$modelSheet$en {
  _Translations$flutter$settings$preferences$modelSheet$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get noneConfigured => 'Keines konfiguriert';
}

// Path: flutter.admin.users.page
class _Translations$flutter$admin$users$page$de extends Translations$flutter$admin$users$page$en {
  _Translations$flutter$admin$users$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get localOnly =>
      'Repolupe auf diesem Gerät hat nur einen Benutzer, daher können keine Benutzer hinzugefügt werden. Um Chats und Repositories mit anderen zu teilen, verwende einen Repolupe-Server.';
  @override
  String get noMatch => 'Keine Benutzer passen zu deiner Suche.';
}

// Path: flutter.admin.users.userPage
class _Translations$flutter$admin$users$userPage$de extends Translations$flutter$admin$users$userPage$en {
  _Translations$flutter$admin$users$userPage$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get login => 'Anmeldung';
  @override
  String get loginAllowed => 'Erlaubt';
  @override
  String get loginDisabled => 'Deaktiviert (überall abgemeldet)';
  @override
  String get repositoriesManage => 'Kann eigene verwalten und teilen';
  @override
  String get repositoriesReadOnly => 'Nur lesen (kann nur Fragen zu Repositories stellen, die mit ihm geteilt wurden)';
  @override
  String get identity => 'Benutzername und E-Mail';
  @override
  String get identityEditable => 'Der Benutzer kann sie ändern';
  @override
  String get identityFixed => 'Fest (nur Admins können sie ändern)';
  @override
  String get passwordMustChange => 'Muss bei der nächsten Anmeldung geändert werden';
}

// Path: flutter.admin.users.form
class _Translations$flutter$admin$users$form$de extends Translations$flutter$admin$users$form$en {
  _Translations$flutter$admin$users$form$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get adminNote => 'Admins können umbenannt, aber nie eingeschränkt werden.';
}

// Path: flutter.admin.users.flags
class _Translations$flutter$admin$users$flags$de extends Translations$flutter$admin$users$flags$en {
  _Translations$flutter$admin$users$flags$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get repositoriesReadOnly => 'Repositories nur lesen';
  @override
  String get identityFixed => 'Benutzername und E-Mail fest';
}

// Path: flutter.admin.llm.page
class _Translations$flutter$admin$llm$page$de extends Translations$flutter$admin$llm$page$en {
  _Translations$flutter$admin$llm$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get apiKeyNone => 'Keiner';
  @override
  String get currencyNone => 'Keine (seine Modelle haben keine Preise)';
  @override
  String get models => 'Modelle';
}

// Path: flutter.admin.llm.providerForm
class _Translations$flutter$admin$llm$providerForm$de extends Translations$flutter$admin$llm$providerForm$en {
  _Translations$flutter$admin$llm$providerForm$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get openAiTitle => 'OpenAI-kompatibel';
  @override
  String get openAiDescription => 'Die OpenAI-Chat-Completions-API, die auch OpenRouter, Ollama, vLLM, LM Studio usw. anbieten.';
  @override
  String get anthropicDescription => 'Die Anthropic-Messages-API.';
  @override
  String get baseUrlHint => 'Leer lassen für die offizielle API des Formats.';
  @override
  String get currencyHint => 'ISO-4217-Code der Modellpreise, z. B. USD oder EUR. Leer lassen, wenn seine Modelle keine Preise haben.';
  @override
  String get apiKeyOptional => 'API-Schlüssel (optional)';
  @override
  String get apiKeyHint => 'Leer lassen für Server ohne Authentifizierung.';
  @override
  String get showKey => 'Schlüssel anzeigen';
  @override
  String get hideKey => 'Schlüssel verbergen';
}

// Path: flutter.admin.llm.modelForm
class _Translations$flutter$admin$llm$modelForm$de extends Translations$flutter$admin$llm$modelForm$en {
  _Translations$flutter$admin$llm$modelForm$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String apiNameHint({required Object max}) => 'Die Modell-ID, die an die API gesendet wird. Höchstens ${max} Zeichen.';
  @override
  String get displayNameOptional => 'Anzeigename (optional)';
  @override
  String displayNameHint({required Object max}) => 'Wird Benutzern statt des API-Namens angezeigt. Höchstens ${max} Zeichen.';
  @override
  String get maxOutputTokensOptional => 'Max. Ausgabe-Tokens (optional)';
  @override
  String get maxOutputTokensHint => 'Leer lassen für den Standardwert des API-Formats.';
}

// Path: flutter.admin.config.page
class _Translations$flutter$admin$config$page$de extends Translations$flutter$admin$config$page$en {
  _Translations$flutter$admin$config$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get runtimeOnly => 'Nur Laufzeiteinstellungen können überschrieben werden, die anderen erfordern einen Neustart.';
  @override
  String get runtime => 'Laufzeit';
  @override
  String overrideValue({required Object value}) => 'Überschreibung: ${value}';
}

// Path: flutter.admin.config.overrideDialog
class _Translations$flutter$admin$config$overrideDialog$de extends Translations$flutter$admin$config$overrideDialog$en {
  _Translations$flutter$admin$config$overrideDialog$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String get remove => 'Überschreibung entfernen';
}

// Path: flutter.admin.extraction.page
class _Translations$flutter$admin$extraction$page$de extends Translations$flutter$admin$extraction$page$en {
  _Translations$flutter$admin$extraction$page$de._(TranslationsDe root) : this._root = root, super.internal(root);

  final TranslationsDe _root; // ignore: unused_field

  // Translations
  @override
  String loadMore({required Object remaining}) => 'Mehr laden (noch ${remaining})';
}
