// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'account.dart';

class AccountMapper extends ClassMapperBase<Account> {
  AccountMapper._();

  static AccountMapper? _instance;
  static AccountMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AccountMapper._());
      AccountUserMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Account';

  static String? _$apiUrl(Account v) => v.apiUrl;
  static const Field<Account, String> _f$apiUrl = Field(
    'apiUrl',
    _$apiUrl,
    key: r'api_url',
  );
  static String _$token(Account v) => v.token;
  static const Field<Account, String> _f$token = Field('token', _$token);
  static AccountUser _$user(Account v) => v.user;
  static const Field<Account, AccountUser> _f$user = Field('user', _$user);

  @override
  final MappableFields<Account> fields = const {
    #apiUrl: _f$apiUrl,
    #token: _f$token,
    #user: _f$user,
  };

  static Account _instantiate(DecodingData data) {
    return Account(
      apiUrl: data.dec(_f$apiUrl),
      token: data.dec(_f$token),
      user: data.dec(_f$user),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Account fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Account>(map);
  }

  static Account fromJson(String json) {
    return ensureInitialized().decodeJson<Account>(json);
  }
}

mixin AccountMappable {
  String toJson() {
    return AccountMapper.ensureInitialized().encodeJson<Account>(
      this as Account,
    );
  }

  Map<String, dynamic> toMap() {
    return AccountMapper.ensureInitialized().encodeMap<Account>(
      this as Account,
    );
  }

  AccountCopyWith<Account, Account, Account> get copyWith =>
      _AccountCopyWithImpl<Account, Account>(
        this as Account,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AccountMapper.ensureInitialized().stringifyValue(this as Account);
  }

  @override
  bool operator ==(Object other) {
    return AccountMapper.ensureInitialized().equalsValue(
      this as Account,
      other,
    );
  }

  @override
  int get hashCode {
    return AccountMapper.ensureInitialized().hashValue(this as Account);
  }
}

extension AccountValueCopy<$R, $Out> on ObjectCopyWith<$R, Account, $Out> {
  AccountCopyWith<$R, Account, $Out> get $asAccount =>
      $base.as((v, t, t2) => _AccountCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AccountCopyWith<$R, $In extends Account, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  AccountUserCopyWith<$R, AccountUser, AccountUser> get user;
  $R call({String? apiUrl, String? token, AccountUser? user});
  AccountCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AccountCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Account, $Out>
    implements AccountCopyWith<$R, Account, $Out> {
  _AccountCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Account> $mapper =
      AccountMapper.ensureInitialized();
  @override
  AccountUserCopyWith<$R, AccountUser, AccountUser> get user =>
      $value.user.copyWith.$chain((v) => call(user: v));
  @override
  $R call({Object? apiUrl = $none, String? token, AccountUser? user}) => $apply(
    FieldCopyWithData({
      if (apiUrl != $none) #apiUrl: apiUrl,
      if (token != null) #token: token,
      if (user != null) #user: user,
    }),
  );
  @override
  Account $make(CopyWithData data) => Account(
    apiUrl: data.get(#apiUrl, or: $value.apiUrl),
    token: data.get(#token, or: $value.token),
    user: data.get(#user, or: $value.user),
  );

  @override
  AccountCopyWith<$R2, Account, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AccountCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AccountUserMapper extends ClassMapperBase<AccountUser> {
  AccountUserMapper._();

  static AccountUserMapper? _instance;
  static AccountUserMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AccountUserMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'AccountUser';

  static String _$id(AccountUser v) => v.id;
  static const Field<AccountUser, String> _f$id = Field('id', _$id);
  static String _$userName(AccountUser v) => v.userName;
  static const Field<AccountUser, String> _f$userName = Field(
    'userName',
    _$userName,
    key: r'user_name',
  );

  @override
  final MappableFields<AccountUser> fields = const {
    #id: _f$id,
    #userName: _f$userName,
  };

  static AccountUser _instantiate(DecodingData data) {
    return AccountUser(id: data.dec(_f$id), userName: data.dec(_f$userName));
  }

  @override
  final Function instantiate = _instantiate;

  static AccountUser fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AccountUser>(map);
  }

  static AccountUser fromJson(String json) {
    return ensureInitialized().decodeJson<AccountUser>(json);
  }
}

mixin AccountUserMappable {
  String toJson() {
    return AccountUserMapper.ensureInitialized().encodeJson<AccountUser>(
      this as AccountUser,
    );
  }

  Map<String, dynamic> toMap() {
    return AccountUserMapper.ensureInitialized().encodeMap<AccountUser>(
      this as AccountUser,
    );
  }

  AccountUserCopyWith<AccountUser, AccountUser, AccountUser> get copyWith =>
      _AccountUserCopyWithImpl<AccountUser, AccountUser>(
        this as AccountUser,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AccountUserMapper.ensureInitialized().stringifyValue(
      this as AccountUser,
    );
  }

  @override
  bool operator ==(Object other) {
    return AccountUserMapper.ensureInitialized().equalsValue(
      this as AccountUser,
      other,
    );
  }

  @override
  int get hashCode {
    return AccountUserMapper.ensureInitialized().hashValue(this as AccountUser);
  }
}

extension AccountUserValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AccountUser, $Out> {
  AccountUserCopyWith<$R, AccountUser, $Out> get $asAccountUser =>
      $base.as((v, t, t2) => _AccountUserCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AccountUserCopyWith<$R, $In extends AccountUser, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, String? userName});
  AccountUserCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AccountUserCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AccountUser, $Out>
    implements AccountUserCopyWith<$R, AccountUser, $Out> {
  _AccountUserCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AccountUser> $mapper =
      AccountUserMapper.ensureInitialized();
  @override
  $R call({String? id, String? userName}) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (userName != null) #userName: userName,
    }),
  );
  @override
  AccountUser $make(CopyWithData data) => AccountUser(
    id: data.get(#id, or: $value.id),
    userName: data.get(#userName, or: $value.userName),
  );

  @override
  AccountUserCopyWith<$R2, AccountUser, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AccountUserCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

