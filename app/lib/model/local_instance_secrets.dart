import 'package:dart_mappable/dart_mappable.dart';

part 'local_instance_secrets.mapper.dart';

/// What the app needs to start the local instance and to log in on it again, generated on its first start.
@MappableClass(caseStyle: CaseStyle.snakeCase)
class LocalInstanceSecrets with LocalInstanceSecretsMappable {
  /// Encrypts the repository access tokens and LLM API keys in the instance's database, which can't be read
  /// anymore with another one.
  final String tokenEncryptionKey;

  /// The user name of the instance's admin, who the app logs in as. Admins can rename themselves.
  final String userName;

  /// The password of the instance's admin, which the user can change.
  final String password;

  LocalInstanceSecrets({
    required this.tokenEncryptionKey,
    required this.userName,
    required this.password,
  });

  /// Without the secrets, which the debug observers would print otherwise.
  @override
  String toString() => 'LocalInstanceSecrets(userName: $userName)';
}
