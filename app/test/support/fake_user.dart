/// The `UserDto` JSON of a fake server, like `GET /api/v1/me` returns it.
Map<String, dynamic> fakeUser({
  required String id,
  String userName = 'alice',
  String? email = 'alice@example.com',
  bool canLogin = true,
  String role = 'USER',
  bool canManageRepositories = true,
  bool canChangeIdentity = true,
  bool mustChangePassword = false,
  String? defaultModelId,
  String? locale,
  bool autoCommit = false,
  String? fullName,
  String? firstName,
  String? about,
}) => {
  'id': id,
  'role': role,
  'user_name': userName,
  'email': email,
  'can_login': canLogin,
  'can_manage_repositories': canManageRepositories,
  'can_change_identity': canChangeIdentity,
  'must_change_password': mustChangePassword,
  'default_model_id': defaultModelId,
  'locale': locale,
  'auto_commit': autoCommit,
  'full_name': fullName,
  'first_name': firstName,
  'about': about,
  'created_at': '2026-10-20T12:00:00+00:00',
};

/// The `ModelDto` JSON of a fake server, like `GET /api/v1/models` lists them.
Map<String, dynamic> fakeModel({
  required String id,
  required String displayName,
  required String providerId,
  required String providerName,
  bool isDefault = false,
}) => {
  'id': id,
  'display_name': displayName,
  'provider_id': providerId,
  'provider_name': providerName,
  'is_default': isDefault,
};

/// The `ErrorDto` JSON of a fake server.
Map<String, dynamic> fakeError(String code, String message) => {'code': code, 'message': message};
