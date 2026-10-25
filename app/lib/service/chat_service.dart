import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

part 'chat_service.mapper.dart';

@MappableClass()
class ChatState with ChatStateMappable {
  /// `null` until the first message is sent.
  final ChatDto? chat;

  /// Oldest first.
  final List<MessageDto> messages;

  /// The models the user can choose, also to show which one wrote an answer.
  final List<ModelDto> models;

  /// The user's own model, used when the chat has none.
  final UuidValue? defaultModelId;

  /// The repositories the user can read, to choose those of a new chat.
  final List<RepositoryDto> repositories;

  /// Whether the new chat reads all repositories of the user (then [repositoryIds] is empty).
  /// The chat keeps the repositories it was created with, see [scopeAll].
  final bool allRepositories;

  /// The repositories the new chat reads, unless [allRepositories].
  final List<UuidValue> repositoryIds;

  /// The model chosen for the new chat, `null` uses the user's model. The chat has its own, see [chosenModelId].
  final UuidValue? modelId;

  /// Whether the new chat is temporary, see [isTemporary].
  final bool temporary;

  /// Whether a message is being sent.
  final bool sending;

  /// Whether a previous chat is being opened, see [OpenChatAction].
  final bool loading;

  /// Whether the models and repositories have been loaded by [NewChatAction].
  final bool loaded;

  /// Incremented by [NewChatAction] and [OpenChatAction], so the results of requests for the previous chat are dropped.
  final int epoch;

  ChatState({
    required this.chat,
    required this.messages,
    required this.models,
    required this.defaultModelId,
    required this.repositories,
    required this.allRepositories,
    required this.repositoryIds,
    required this.modelId,
    required this.temporary,
    required this.sending,
    required this.loading,
    required this.loaded,
    required this.epoch,
  });

  ChatState.empty()
    : this(
        chat: null,
        messages: const [],
        models: const [],
        defaultModelId: null,
        repositories: const [],
        allRepositories: false,
        repositoryIds: const [],
        modelId: null,
        temporary: false,
        sending: false,
        loading: false,
        loaded: false,
        epoch: 0,
      );

  /// The answer being generated, at most one per chat.
  /// Its content stays as it was sent until it is finished, the [MessageService] has the current one.
  MessageDto? get answer => messages.where((m) => m.status == MessageStatus.generating).lastOrNull;

  /// The name of the model [modelId], `null` if it no longer exists.
  String? modelName(UuidValue? modelId) => models.where((m) => m.id == modelId).firstOrNull?.displayName;

  /// Whether the chat (or the new one) reads all repositories of the user.
  bool get scopeAll => chat?.allRepositories ?? allRepositories;

  /// The repositories the chat (or the new one) reads, unless [scopeAll].
  List<UuidValue> get scopeIds => chat?.repositoryIds ?? repositoryIds;

  /// The model chosen for the chat (or the new one), `null` for the user's model.
  UuidValue? get chosenModelId => chat == null ? modelId : chat!.modelId;

  /// Whether the chat (or the new one) is temporary: not listed in the drawer, and deleted a day after its last message.
  /// It is fixed once the chat is created.
  bool get isTemporary => chat?.temporary ?? temporary;

  /// The model the user's model resolves to, like the server picks it: the user's own, else the default model.
  ModelDto? get fallbackModel => models.where((m) => m.id == defaultModelId).firstOrNull ?? models.where((m) => m.isDefault).firstOrNull;

  /// The model that answers in the chat: the chosen one, else the [fallbackModel].
  /// A model that no longer exists counts as not chosen, like on the server.
  ModelDto? get answeringModel => models.where((m) => m.id == chosenModelId).firstOrNull ?? fallbackModel;
}

final chatProvider = ReduxProvider<ChatService, ChatState>((ref) {
  return ChatService(
    api: ref.notifier(apiProvider),
    messages: ref.notifier(messageProvider),
  );
});

/// One chat of the active account: a new one, whose repositories and model can be chosen, or a previous one opened
/// with its messages, whose model can be changed.
class ChatService extends ReduxNotifier<ChatState> {
  final ApiService _api;
  final MessageService _messages;

  ChatService({
    required this._api,
    required this._messages,
  });

  @override
  ChatState init() => ChatState.empty();
}

/// Starts a new chat for the active account (dropping the current one) and loads the models, the user's model and the
/// repositories. The new chat reads all repositories, if there are any, or only [repositoryIds] if given (e.g. opened
/// from a repository's page).
class NewChatAction extends AsyncReduxAction<ChatService, ChatState> {
  final List<UuidValue>? repositoryIds;

  NewChatAction({this.repositoryIds});

  @override
  Future<ChatState> reduce() async {
    external(notifier._messages).dispatch(StopFollowMessageAction());
    final epoch = dispatch(_IncrementEpochAction()).epoch;
    dispatch(_SetStateAction(ChatState.empty().copyWith(epoch: epoch)));
    if (notifier._api.state == null) {
      return state.copyWith(loaded: true);
    }

    final api = external(notifier._api);
    final (models, user, repositories) = await (
      _loadOrNull(() => api.dispatchAsyncTakeResult(ApiListModelsAction())),
      _loadOrNull(() => api.dispatchAsyncTakeResult(ApiGetMeAction())),
      _loadOrNull(() => api.dispatchAsyncTakeResult(ApiListRepositoriesAction())),
    ).wait;
    if (epoch != state.epoch) {
      return state;
    }
    final repositoryIds = this.repositoryIds;
    return state.copyWith(
      models: models ?? const [],
      defaultModelId: user?.defaultModelId,
      repositories: repositories ?? const [],
      // Without repositories, "all" would be misleading.
      allRepositories: repositoryIds == null && repositories != null && repositories.isNotEmpty,
      repositoryIds: repositoryIds ?? const [],
      loaded: true,
    );
  }

  @override
  String toString() => 'NewChatAction(repositoryIds: $repositoryIds)';

  /// Without what fails to load, only the choices are missing then. The failed request is logged as an action.
  Future<T?> _loadOrNull<T>(Future<T> Function() load) async {
    try {
      return await load();
    } on ClientError {
      return null;
    }
  }
}

/// Opens the previous chat [chatId] with its messages (dropping the current one), and follows its answer if one is
/// being generated. Shows a snack bar if it fails, leaving a new chat.
class OpenChatAction extends AsyncReduxAction<ChatService, ChatState> with GlobalActions {
  final UuidValue chatId;

  OpenChatAction(this.chatId);

  @override
  Future<ChatState> reduce() async {
    if (notifier._api.state == null || state.chat?.id == chatId) {
      return state;
    }

    external(notifier._messages).dispatch(StopFollowMessageAction());
    final epoch = dispatch(_IncrementEpochAction()).epoch;
    // The models and repositories belong to the account, which stays the same.
    dispatch(
      _SetStateAction(
        ChatState.empty().copyWith(
          models: state.models,
          defaultModelId: state.defaultModelId,
          repositories: state.repositories,
          loading: true,
          loaded: state.loaded,
          epoch: epoch,
        ),
      ),
    );
    final ChatDetailDto detail;
    try {
      detail = await external(notifier._api).dispatchAsyncTakeResult(ApiGetChatAction(chatId: chatId));
    } on ClientError catch (e) {
      if (epoch != state.epoch) {
        return state;
      }
      global.dispatch(ShowSnackBarAction(message: t.base.chat.page.openFailed(error: e.userMessage)));
      return state.copyWith(loading: false);
    }

    if (epoch != state.epoch) {
      return state;
    }
    final next = state.copyWith(chat: detail.chat, messages: detail.messages, loading: false);
    final answer = next.answer;
    if (answer != null) {
      // Runs until the answer is finished, or until the next chat.
      unawaited(dispatchAsync(_FollowAnswerAction(answer)));
    }
    return next;
  }

  @override
  String toString() => 'OpenChatAction($chatId)';
}

/// Sends [content] (creating the chat with it if there is none yet) and follows the answer.
/// Returns whether it was sent; shows a snack bar if it fails.
class SendMessageAction extends AsyncReduxActionWithResult<ChatService, ChatState, bool> with GlobalActions {
  final String content;

  SendMessageAction(this.content);

  @override
  Future<(ChatState, bool)> reduce() async {
    if (notifier._api.state == null || state.loading || state.sending || state.answer != null || content.trim().isEmpty) {
      return (state, false);
    }

    final epoch = state.epoch;
    final chat = state.chat;
    dispatch(_SetStateAction(state.copyWith(sending: true)));
    (ChatDto, List<MessageDto>) sent;
    try {
      if (chat == null) {
        final detail = await external(notifier._api).dispatchAsyncTakeResult(
          ApiCreateChatAction(
            content: content,
            allRepositories: state.allRepositories,
            repositoryIds: state.repositoryIds,
            modelId: state.modelId,
            temporary: state.temporary,
          ),
        );
        sent = (detail.chat, detail.messages);
      } else {
        final messages = await external(
          notifier._api,
        ).dispatchAsyncTakeResult(ApiSendMessageAction(chatId: chat.id, content: content));
        sent = (chat, messages);
      }
    } on ClientError catch (e) {
      if (epoch != state.epoch) {
        return (state, false);
      }
      global.dispatch(ShowSnackBarAction(message: t.base.chat.page.sendFailed(error: e.userMessage)));
      return (state.copyWith(sending: false), false);
    }

    if (epoch != state.epoch) {
      return (state, false);
    }
    final (newChat, newMessages) = sent;
    final next = state.copyWith(
      chat: newChat,
      messages: [...state.messages, ...newMessages],
      sending: false,
    );
    final answer = next.answer;
    if (answer != null) {
      // Runs until the answer is finished, or until the next chat.
      unawaited(dispatchAsync(_FollowAnswerAction(answer)));
    }
    return (next, true);
  }

  @override
  String toString() => 'SendMessageAction(${content.length} chars)';
}

/// Chooses the repositories of the new chat: all of the user's if [all], else [ids].
/// A chat keeps the repositories it was created with, so this does nothing once it exists.
class SetRepositoryScopeAction extends ReduxAction<ChatService, ChatState> {
  final bool all;
  final List<UuidValue> ids;

  SetRepositoryScopeAction({required this.all, required this.ids});

  @override
  ChatState reduce() {
    if (state.chat != null) {
      return state;
    }
    return state.copyWith(allRepositories: all, repositoryIds: all ? const [] : ids);
  }

  @override
  String toString() => 'SetRepositoryScopeAction(all: $all, ids: $ids)';
}

/// Makes the new chat temporary or not, see [ChatState.isTemporary].
/// A chat stays as it was created, so this does nothing once it exists.
class SetTemporaryAction extends ReduxAction<ChatService, ChatState> {
  final bool temporary;

  SetTemporaryAction(this.temporary);

  @override
  ChatState reduce() {
    if (state.chat != null) {
      return state;
    }
    return state.copyWith(temporary: temporary);
  }

  @override
  String toString() => 'SetTemporaryAction($temporary)';
}

/// Lets [modelId] answer in the chat (`null` uses the user's model): in the new chat once it is created, in an
/// existing one from its next answer on. Shows a snack bar if it fails.
class ChooseModelAction extends AsyncReduxAction<ChatService, ChatState> with GlobalActions {
  final UuidValue? modelId;

  ChooseModelAction(this.modelId);

  @override
  Future<ChatState> reduce() async {
    final chat = state.chat;
    if (chat == null) {
      return state.copyWith(modelId: modelId);
    }
    if (notifier._api.state == null || chat.modelId == modelId) {
      return state;
    }

    final epoch = state.epoch;
    final ChatDto updated;
    try {
      updated = await external(
        notifier._api,
      ).dispatchAsyncTakeResult(ApiUpdateChatAction(chatId: chat.id, title: chat.title, modelId: modelId));
    } on ClientError catch (e) {
      global.dispatch(
        ShowSnackBarAction(
          message: e.code == ErrorCode.unknownModel ? t.base.chat.unknownModel : t.base.chat.page.changeModelFailed(error: e.userMessage),
        ),
      );
      return state;
    }
    if (epoch != state.epoch) {
      return state;
    }
    return state.copyWith(chat: updated);
  }

  @override
  String toString() => 'ChooseModelAction($modelId)';
}

/// Stops the answer being generated. Its stream then ends with the cancelled message, which is put into the chat.
class CancelAnswerAction extends AsyncReduxAction<ChatService, ChatState> with GlobalActions {
  @override
  Future<ChatState> reduce() async {
    final chat = state.chat;
    final answer = state.answer;
    if (notifier._api.state == null || chat == null || answer == null) {
      return state;
    }

    try {
      await external(notifier._api).dispatchAsync(ApiCancelMessageAction(chatId: chat.id, messageId: answer.id));
    } on ClientError catch (e) {
      global.dispatch(ShowSnackBarAction(message: t.base.chat.page.stopFailed(error: e.userMessage)));
    }
    return state;
  }
}

/// Follows [answer] with the [MessageService] and puts it into the chat once it is finished.
class _FollowAnswerAction extends AsyncReduxAction<ChatService, ChatState> {
  final MessageDto answer;

  _FollowAnswerAction(this.answer);

  @override
  Future<ChatState> reduce() async {
    final chat = state.chat;
    if (notifier._api.state == null || chat == null) {
      return state;
    }

    final epoch = state.epoch;
    final finished = await external(
      notifier._messages,
    ).dispatchAsyncTakeResult(FollowMessageAction(chatId: chat.id, message: answer));
    if (finished == null || epoch != state.epoch) {
      return state;
    }
    return state.copyWith(
      messages: [for (final m in state.messages) m.id == finished.id ? finished : m],
    );
  }

  @override
  String toString() => '_FollowAnswerAction(${answer.id})';
}

class _IncrementEpochAction extends ReduxAction<ChatService, ChatState> {
  @override
  ChatState reduce() => state.copyWith(epoch: state.epoch + 1);
}

class _SetStateAction extends ReduxAction<ChatService, ChatState> {
  final ChatState next;

  _SetStateAction(this.next);

  @override
  ChatState reduce() => next;
}
