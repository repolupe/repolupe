import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/auth.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'account.mapper.dart';

/// A user logged in on a Repolupe server, or on the local instance running in the app.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class Account with AccountMappable {
  /// The server's origin, e.g. `https://repolupe.example.com`, see `normalizeApiUrl`.
  /// `null` for the local instance.
  final String? apiUrl;

  /// The session token, sent as `Authorization: Bearer`.
  final String token;

  /// The user as of the login.
  final AccountUser user;

  Account({
    required this.apiUrl,
    required this.token,
    required this.user,
  });

  Account.fromLogin({required String? apiUrl, required LoginResponse response})
    : this(
        apiUrl: apiUrl,
        token: response.token,
        user: AccountUser(id: response.user.id.uuid, userName: response.user.userName),
      );

  /// Whether the account is on the local instance, see `LocalInstanceService`.
  bool get isLocal => apiUrl == null;

  /// Identifies the account, the same user on the same server is one account.
  String get key => '${apiUrl ?? 'local'}#${user.id}';

  /// The server without the scheme, e.g. `repolupe.example.com`, or `This device` for the local instance.
  String get server => apiUrl?.replaceFirst(RegExp('^https?://'), '') ?? t.flutter.account.thisDevice;

  /// Without the token, which the debug observers would print otherwise.
  @override
  String toString() => 'Account(apiUrl: $apiUrl, user: ${user.userName})';
}

/// What the account keeps of the user (the API's `UserDto`) to identify and show it.
/// Accounts stored with the whole `UserDto` still parse, the other fields are ignored.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class AccountUser with AccountUserMappable {
  /// The user's UUID.
  final String id;

  final String userName;

  AccountUser({
    required this.id,
    required this.userName,
  });
}
