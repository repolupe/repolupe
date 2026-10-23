// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'account_service.dart';

class AccountStateMapper extends ClassMapperBase<AccountState> {
  AccountStateMapper._();

  static AccountStateMapper? _instance;
  static AccountStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AccountStateMapper._());
      AccountMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AccountState';

  static List<Account> _$accounts(AccountState v) => v.accounts;
  static const Field<AccountState, List<Account>> _f$accounts = Field(
    'accounts',
    _$accounts,
  );
  static String? _$activeKey(AccountState v) => v.activeKey;
  static const Field<AccountState, String> _f$activeKey = Field(
    'activeKey',
    _$activeKey,
  );

  @override
  final MappableFields<AccountState> fields = const {
    #accounts: _f$accounts,
    #activeKey: _f$activeKey,
  };

  static AccountState _instantiate(DecodingData data) {
    return AccountState(
      accounts: data.dec(_f$accounts),
      activeKey: data.dec(_f$activeKey),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AccountState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AccountState>(map);
  }

  static AccountState fromJson(String json) {
    return ensureInitialized().decodeJson<AccountState>(json);
  }
}

mixin AccountStateMappable {
  String toJson() {
    return AccountStateMapper.ensureInitialized().encodeJson<AccountState>(
      this as AccountState,
    );
  }

  Map<String, dynamic> toMap() {
    return AccountStateMapper.ensureInitialized().encodeMap<AccountState>(
      this as AccountState,
    );
  }

  AccountStateCopyWith<AccountState, AccountState, AccountState> get copyWith =>
      _AccountStateCopyWithImpl<AccountState, AccountState>(
        this as AccountState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AccountStateMapper.ensureInitialized().stringifyValue(
      this as AccountState,
    );
  }

  @override
  bool operator ==(Object other) {
    return AccountStateMapper.ensureInitialized().equalsValue(
      this as AccountState,
      other,
    );
  }

  @override
  int get hashCode {
    return AccountStateMapper.ensureInitialized().hashValue(
      this as AccountState,
    );
  }
}

extension AccountStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AccountState, $Out> {
  AccountStateCopyWith<$R, AccountState, $Out> get $asAccountState =>
      $base.as((v, t, t2) => _AccountStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AccountStateCopyWith<$R, $In extends AccountState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, Account, AccountCopyWith<$R, Account, Account>> get accounts;
  $R call({List<Account>? accounts, String? activeKey});
  AccountStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AccountStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AccountState, $Out>
    implements AccountStateCopyWith<$R, AccountState, $Out> {
  _AccountStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AccountState> $mapper =
      AccountStateMapper.ensureInitialized();
  @override
  ListCopyWith<$R, Account, AccountCopyWith<$R, Account, Account>>
  get accounts => ListCopyWith(
    $value.accounts,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(accounts: v),
  );
  @override
  $R call({List<Account>? accounts, Object? activeKey = $none}) => $apply(
    FieldCopyWithData({
      if (accounts != null) #accounts: accounts,
      if (activeKey != $none) #activeKey: activeKey,
    }),
  );
  @override
  AccountState $make(CopyWithData data) => AccountState(
    accounts: data.get(#accounts, or: $value.accounts),
    activeKey: data.get(#activeKey, or: $value.activeKey),
  );

  @override
  AccountStateCopyWith<$R2, AccountState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AccountStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

