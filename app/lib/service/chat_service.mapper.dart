// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'chat_service.dart';

class PendingAttachmentMapper extends ClassMapperBase<PendingAttachment> {
  PendingAttachmentMapper._();

  static PendingAttachmentMapper? _instance;
  static PendingAttachmentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PendingAttachmentMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PendingAttachment';

  static int _$key(PendingAttachment v) => v.key;
  static const Field<PendingAttachment, int> _f$key = Field('key', _$key);
  static String _$fileName(PendingAttachment v) => v.fileName;
  static const Field<PendingAttachment, String> _f$fileName = Field(
    'fileName',
    _$fileName,
  );
  static int _$size(PendingAttachment v) => v.size;
  static const Field<PendingAttachment, int> _f$size = Field('size', _$size);
  static AttachmentDto? _$uploaded(PendingAttachment v) => v.uploaded;
  static const Field<PendingAttachment, AttachmentDto> _f$uploaded = Field(
    'uploaded',
    _$uploaded,
  );

  @override
  final MappableFields<PendingAttachment> fields = const {
    #key: _f$key,
    #fileName: _f$fileName,
    #size: _f$size,
    #uploaded: _f$uploaded,
  };

  static PendingAttachment _instantiate(DecodingData data) {
    return PendingAttachment(
      key: data.dec(_f$key),
      fileName: data.dec(_f$fileName),
      size: data.dec(_f$size),
      uploaded: data.dec(_f$uploaded),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PendingAttachment fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PendingAttachment>(map);
  }

  static PendingAttachment fromJson(String json) {
    return ensureInitialized().decodeJson<PendingAttachment>(json);
  }
}

mixin PendingAttachmentMappable {
  String toJson() {
    return PendingAttachmentMapper.ensureInitialized()
        .encodeJson<PendingAttachment>(this as PendingAttachment);
  }

  Map<String, dynamic> toMap() {
    return PendingAttachmentMapper.ensureInitialized()
        .encodeMap<PendingAttachment>(this as PendingAttachment);
  }

  PendingAttachmentCopyWith<
    PendingAttachment,
    PendingAttachment,
    PendingAttachment
  >
  get copyWith =>
      _PendingAttachmentCopyWithImpl<PendingAttachment, PendingAttachment>(
        this as PendingAttachment,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return PendingAttachmentMapper.ensureInitialized().stringifyValue(
      this as PendingAttachment,
    );
  }

  @override
  bool operator ==(Object other) {
    return PendingAttachmentMapper.ensureInitialized().equalsValue(
      this as PendingAttachment,
      other,
    );
  }

  @override
  int get hashCode {
    return PendingAttachmentMapper.ensureInitialized().hashValue(
      this as PendingAttachment,
    );
  }
}

extension PendingAttachmentValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PendingAttachment, $Out> {
  PendingAttachmentCopyWith<$R, PendingAttachment, $Out>
  get $asPendingAttachment => $base.as(
    (v, t, t2) => _PendingAttachmentCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class PendingAttachmentCopyWith<
  $R,
  $In extends PendingAttachment,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? key, String? fileName, int? size, AttachmentDto? uploaded});
  PendingAttachmentCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PendingAttachmentCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PendingAttachment, $Out>
    implements PendingAttachmentCopyWith<$R, PendingAttachment, $Out> {
  _PendingAttachmentCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PendingAttachment> $mapper =
      PendingAttachmentMapper.ensureInitialized();
  @override
  $R call({int? key, String? fileName, int? size, Object? uploaded = $none}) =>
      $apply(
        FieldCopyWithData({
          if (key != null) #key: key,
          if (fileName != null) #fileName: fileName,
          if (size != null) #size: size,
          if (uploaded != $none) #uploaded: uploaded,
        }),
      );
  @override
  PendingAttachment $make(CopyWithData data) => PendingAttachment(
    key: data.get(#key, or: $value.key),
    fileName: data.get(#fileName, or: $value.fileName),
    size: data.get(#size, or: $value.size),
    uploaded: data.get(#uploaded, or: $value.uploaded),
  );

  @override
  PendingAttachmentCopyWith<$R2, PendingAttachment, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PendingAttachmentCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ChatStateMapper extends ClassMapperBase<ChatState> {
  ChatStateMapper._();

  static ChatStateMapper? _instance;
  static ChatStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChatStateMapper._());
      PendingAttachmentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ChatState';

  static ChatDto? _$chat(ChatState v) => v.chat;
  static const Field<ChatState, ChatDto> _f$chat = Field('chat', _$chat);
  static List<MessageDto> _$messages(ChatState v) => v.messages;
  static const Field<ChatState, List<MessageDto>> _f$messages = Field(
    'messages',
    _$messages,
  );
  static List<ModelDto> _$models(ChatState v) => v.models;
  static const Field<ChatState, List<ModelDto>> _f$models = Field(
    'models',
    _$models,
  );
  static UuidValue? _$defaultModelId(ChatState v) => v.defaultModelId;
  static const Field<ChatState, UuidValue> _f$defaultModelId = Field(
    'defaultModelId',
    _$defaultModelId,
  );
  static List<RepositoryDto> _$repositories(ChatState v) => v.repositories;
  static const Field<ChatState, List<RepositoryDto>> _f$repositories = Field(
    'repositories',
    _$repositories,
  );
  static bool _$allRepositories(ChatState v) => v.allRepositories;
  static const Field<ChatState, bool> _f$allRepositories = Field(
    'allRepositories',
    _$allRepositories,
  );
  static List<UuidValue> _$repositoryIds(ChatState v) => v.repositoryIds;
  static const Field<ChatState, List<UuidValue>> _f$repositoryIds = Field(
    'repositoryIds',
    _$repositoryIds,
  );
  static UuidValue? _$modelId(ChatState v) => v.modelId;
  static const Field<ChatState, UuidValue> _f$modelId = Field(
    'modelId',
    _$modelId,
  );
  static bool _$temporary(ChatState v) => v.temporary;
  static const Field<ChatState, bool> _f$temporary = Field(
    'temporary',
    _$temporary,
  );
  static PendingAttachment? _$attachment(ChatState v) => v.attachment;
  static const Field<ChatState, PendingAttachment> _f$attachment = Field(
    'attachment',
    _$attachment,
  );
  static bool _$sending(ChatState v) => v.sending;
  static const Field<ChatState, bool> _f$sending = Field('sending', _$sending);
  static bool _$loading(ChatState v) => v.loading;
  static const Field<ChatState, bool> _f$loading = Field('loading', _$loading);
  static bool _$loaded(ChatState v) => v.loaded;
  static const Field<ChatState, bool> _f$loaded = Field('loaded', _$loaded);
  static int _$epoch(ChatState v) => v.epoch;
  static const Field<ChatState, int> _f$epoch = Field('epoch', _$epoch);

  @override
  final MappableFields<ChatState> fields = const {
    #chat: _f$chat,
    #messages: _f$messages,
    #models: _f$models,
    #defaultModelId: _f$defaultModelId,
    #repositories: _f$repositories,
    #allRepositories: _f$allRepositories,
    #repositoryIds: _f$repositoryIds,
    #modelId: _f$modelId,
    #temporary: _f$temporary,
    #attachment: _f$attachment,
    #sending: _f$sending,
    #loading: _f$loading,
    #loaded: _f$loaded,
    #epoch: _f$epoch,
  };

  static ChatState _instantiate(DecodingData data) {
    return ChatState(
      chat: data.dec(_f$chat),
      messages: data.dec(_f$messages),
      models: data.dec(_f$models),
      defaultModelId: data.dec(_f$defaultModelId),
      repositories: data.dec(_f$repositories),
      allRepositories: data.dec(_f$allRepositories),
      repositoryIds: data.dec(_f$repositoryIds),
      modelId: data.dec(_f$modelId),
      temporary: data.dec(_f$temporary),
      attachment: data.dec(_f$attachment),
      sending: data.dec(_f$sending),
      loading: data.dec(_f$loading),
      loaded: data.dec(_f$loaded),
      epoch: data.dec(_f$epoch),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChatState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChatState>(map);
  }

  static ChatState fromJson(String json) {
    return ensureInitialized().decodeJson<ChatState>(json);
  }
}

mixin ChatStateMappable {
  String toJson() {
    return ChatStateMapper.ensureInitialized().encodeJson<ChatState>(
      this as ChatState,
    );
  }

  Map<String, dynamic> toMap() {
    return ChatStateMapper.ensureInitialized().encodeMap<ChatState>(
      this as ChatState,
    );
  }

  ChatStateCopyWith<ChatState, ChatState, ChatState> get copyWith =>
      _ChatStateCopyWithImpl<ChatState, ChatState>(
        this as ChatState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ChatStateMapper.ensureInitialized().stringifyValue(
      this as ChatState,
    );
  }

  @override
  bool operator ==(Object other) {
    return ChatStateMapper.ensureInitialized().equalsValue(
      this as ChatState,
      other,
    );
  }

  @override
  int get hashCode {
    return ChatStateMapper.ensureInitialized().hashValue(this as ChatState);
  }
}

extension ChatStateValueCopy<$R, $Out> on ObjectCopyWith<$R, ChatState, $Out> {
  ChatStateCopyWith<$R, ChatState, $Out> get $asChatState =>
      $base.as((v, t, t2) => _ChatStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ChatStateCopyWith<$R, $In extends ChatState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, MessageDto, ObjectCopyWith<$R, MessageDto, MessageDto>>
  get messages;
  ListCopyWith<$R, ModelDto, ObjectCopyWith<$R, ModelDto, ModelDto>> get models;
  ListCopyWith<
    $R,
    RepositoryDto,
    ObjectCopyWith<$R, RepositoryDto, RepositoryDto>
  >
  get repositories;
  ListCopyWith<$R, UuidValue, ObjectCopyWith<$R, UuidValue, UuidValue>>
  get repositoryIds;
  PendingAttachmentCopyWith<$R, PendingAttachment, PendingAttachment>?
  get attachment;
  $R call({
    ChatDto? chat,
    List<MessageDto>? messages,
    List<ModelDto>? models,
    UuidValue? defaultModelId,
    List<RepositoryDto>? repositories,
    bool? allRepositories,
    List<UuidValue>? repositoryIds,
    UuidValue? modelId,
    bool? temporary,
    PendingAttachment? attachment,
    bool? sending,
    bool? loading,
    bool? loaded,
    int? epoch,
  });
  ChatStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ChatStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ChatState, $Out>
    implements ChatStateCopyWith<$R, ChatState, $Out> {
  _ChatStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ChatState> $mapper =
      ChatStateMapper.ensureInitialized();
  @override
  ListCopyWith<$R, MessageDto, ObjectCopyWith<$R, MessageDto, MessageDto>>
  get messages => ListCopyWith(
    $value.messages,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(messages: v),
  );
  @override
  ListCopyWith<$R, ModelDto, ObjectCopyWith<$R, ModelDto, ModelDto>>
  get models => ListCopyWith(
    $value.models,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(models: v),
  );
  @override
  ListCopyWith<
    $R,
    RepositoryDto,
    ObjectCopyWith<$R, RepositoryDto, RepositoryDto>
  >
  get repositories => ListCopyWith(
    $value.repositories,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(repositories: v),
  );
  @override
  ListCopyWith<$R, UuidValue, ObjectCopyWith<$R, UuidValue, UuidValue>>
  get repositoryIds => ListCopyWith(
    $value.repositoryIds,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(repositoryIds: v),
  );
  @override
  PendingAttachmentCopyWith<$R, PendingAttachment, PendingAttachment>?
  get attachment =>
      $value.attachment?.copyWith.$chain((v) => call(attachment: v));
  @override
  $R call({
    Object? chat = $none,
    List<MessageDto>? messages,
    List<ModelDto>? models,
    Object? defaultModelId = $none,
    List<RepositoryDto>? repositories,
    bool? allRepositories,
    List<UuidValue>? repositoryIds,
    Object? modelId = $none,
    bool? temporary,
    Object? attachment = $none,
    bool? sending,
    bool? loading,
    bool? loaded,
    int? epoch,
  }) => $apply(
    FieldCopyWithData({
      if (chat != $none) #chat: chat,
      if (messages != null) #messages: messages,
      if (models != null) #models: models,
      if (defaultModelId != $none) #defaultModelId: defaultModelId,
      if (repositories != null) #repositories: repositories,
      if (allRepositories != null) #allRepositories: allRepositories,
      if (repositoryIds != null) #repositoryIds: repositoryIds,
      if (modelId != $none) #modelId: modelId,
      if (temporary != null) #temporary: temporary,
      if (attachment != $none) #attachment: attachment,
      if (sending != null) #sending: sending,
      if (loading != null) #loading: loading,
      if (loaded != null) #loaded: loaded,
      if (epoch != null) #epoch: epoch,
    }),
  );
  @override
  ChatState $make(CopyWithData data) => ChatState(
    chat: data.get(#chat, or: $value.chat),
    messages: data.get(#messages, or: $value.messages),
    models: data.get(#models, or: $value.models),
    defaultModelId: data.get(#defaultModelId, or: $value.defaultModelId),
    repositories: data.get(#repositories, or: $value.repositories),
    allRepositories: data.get(#allRepositories, or: $value.allRepositories),
    repositoryIds: data.get(#repositoryIds, or: $value.repositoryIds),
    modelId: data.get(#modelId, or: $value.modelId),
    temporary: data.get(#temporary, or: $value.temporary),
    attachment: data.get(#attachment, or: $value.attachment),
    sending: data.get(#sending, or: $value.sending),
    loading: data.get(#loading, or: $value.loading),
    loaded: data.get(#loaded, or: $value.loaded),
    epoch: data.get(#epoch, or: $value.epoch),
  );

  @override
  ChatStateCopyWith<$R2, ChatState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ChatStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

