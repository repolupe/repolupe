import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:uuid/uuid.dart';

/// A `UserDto`, like `GET /api/v1/me` returns it.
UserDto fakeUser({
  required String id,
  String userName = 'alice',
  String? email = 'alice@example.com',
  bool canLogin = true,
  UserRole role = UserRole.user,
  bool canManageRepositories = true,
  bool canChangeIdentity = true,
  bool mustChangePassword = false,
  String? defaultModelId,
  String? locale,
  bool autoCommit = false,
  String? fullName,
  String? firstName,
  String? about,
}) => UserDto(
  id: UuidValue.fromString(id),
  role: role,
  userName: userName,
  email: email,
  canLogin: canLogin,
  canManageRepositories: canManageRepositories,
  canChangeIdentity: canChangeIdentity,
  mustChangePassword: mustChangePassword,
  defaultModelId: defaultModelId == null ? null : UuidValue.fromString(defaultModelId),
  locale: locale,
  autoCommit: autoCommit,
  fullName: fullName,
  firstName: firstName,
  about: about,
  createdAt: DateTime.utc(2026, 10, 20, 12),
);

/// A `ModelDto`, like `GET /api/v1/models` lists them.
ModelDto fakeModel({
  required String id,
  required String displayName,
  required String providerId,
  required String providerName,
  bool isDefault = false,
}) => ModelDto(
  id: UuidValue.fromString(id),
  displayName: displayName,
  providerId: UuidValue.fromString(providerId),
  providerName: providerName,
  isDefault: isDefault,
);
