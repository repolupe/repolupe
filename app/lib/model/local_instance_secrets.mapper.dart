// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'local_instance_secrets.dart';

class LocalInstanceSecretsMapper extends ClassMapperBase<LocalInstanceSecrets> {
  LocalInstanceSecretsMapper._();

  static LocalInstanceSecretsMapper? _instance;
  static LocalInstanceSecretsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LocalInstanceSecretsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'LocalInstanceSecrets';

  static String _$tokenEncryptionKey(LocalInstanceSecrets v) =>
      v.tokenEncryptionKey;
  static const Field<LocalInstanceSecrets, String> _f$tokenEncryptionKey =
      Field(
        'tokenEncryptionKey',
        _$tokenEncryptionKey,
        key: r'token_encryption_key',
      );
  static String _$userName(LocalInstanceSecrets v) => v.userName;
  static const Field<LocalInstanceSecrets, String> _f$userName = Field(
    'userName',
    _$userName,
    key: r'user_name',
  );
  static String _$password(LocalInstanceSecrets v) => v.password;
  static const Field<LocalInstanceSecrets, String> _f$password = Field(
    'password',
    _$password,
  );

  @override
  final MappableFields<LocalInstanceSecrets> fields = const {
    #tokenEncryptionKey: _f$tokenEncryptionKey,
    #userName: _f$userName,
    #password: _f$password,
  };

  static LocalInstanceSecrets _instantiate(DecodingData data) {
    return LocalInstanceSecrets(
      tokenEncryptionKey: data.dec(_f$tokenEncryptionKey),
      userName: data.dec(_f$userName),
      password: data.dec(_f$password),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LocalInstanceSecrets fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LocalInstanceSecrets>(map);
  }

  static LocalInstanceSecrets fromJson(String json) {
    return ensureInitialized().decodeJson<LocalInstanceSecrets>(json);
  }
}

mixin LocalInstanceSecretsMappable {
  String toJson() {
    return LocalInstanceSecretsMapper.ensureInitialized()
        .encodeJson<LocalInstanceSecrets>(this as LocalInstanceSecrets);
  }

  Map<String, dynamic> toMap() {
    return LocalInstanceSecretsMapper.ensureInitialized()
        .encodeMap<LocalInstanceSecrets>(this as LocalInstanceSecrets);
  }

  LocalInstanceSecretsCopyWith<
    LocalInstanceSecrets,
    LocalInstanceSecrets,
    LocalInstanceSecrets
  >
  get copyWith =>
      _LocalInstanceSecretsCopyWithImpl<
        LocalInstanceSecrets,
        LocalInstanceSecrets
      >(this as LocalInstanceSecrets, $identity, $identity);
  @override
  String toString() {
    return LocalInstanceSecretsMapper.ensureInitialized().stringifyValue(
      this as LocalInstanceSecrets,
    );
  }

  @override
  bool operator ==(Object other) {
    return LocalInstanceSecretsMapper.ensureInitialized().equalsValue(
      this as LocalInstanceSecrets,
      other,
    );
  }

  @override
  int get hashCode {
    return LocalInstanceSecretsMapper.ensureInitialized().hashValue(
      this as LocalInstanceSecrets,
    );
  }
}

extension LocalInstanceSecretsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LocalInstanceSecrets, $Out> {
  LocalInstanceSecretsCopyWith<$R, LocalInstanceSecrets, $Out>
  get $asLocalInstanceSecrets => $base.as(
    (v, t, t2) => _LocalInstanceSecretsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LocalInstanceSecretsCopyWith<
  $R,
  $In extends LocalInstanceSecrets,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? tokenEncryptionKey, String? userName, String? password});
  LocalInstanceSecretsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LocalInstanceSecretsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LocalInstanceSecrets, $Out>
    implements LocalInstanceSecretsCopyWith<$R, LocalInstanceSecrets, $Out> {
  _LocalInstanceSecretsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LocalInstanceSecrets> $mapper =
      LocalInstanceSecretsMapper.ensureInitialized();
  @override
  $R call({String? tokenEncryptionKey, String? userName, String? password}) =>
      $apply(
        FieldCopyWithData({
          if (tokenEncryptionKey != null)
            #tokenEncryptionKey: tokenEncryptionKey,
          if (userName != null) #userName: userName,
          if (password != null) #password: password,
        }),
      );
  @override
  LocalInstanceSecrets $make(CopyWithData data) => LocalInstanceSecrets(
    tokenEncryptionKey: data.get(
      #tokenEncryptionKey,
      or: $value.tokenEncryptionKey,
    ),
    userName: data.get(#userName, or: $value.userName),
    password: data.get(#password, or: $value.password),
  );

  @override
  LocalInstanceSecretsCopyWith<$R2, LocalInstanceSecrets, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LocalInstanceSecretsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

