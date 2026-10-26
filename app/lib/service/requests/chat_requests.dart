part of '../api_service.dart';

/// Lists the models the user can choose.
class ApiListModelsAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<ModelDto>> {
  ApiListModelsAction();

  @override
  Future<(AccountClient?, List<ModelDto>)> reduce() async {
    final models = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listModels(),
      ),
    );
    return (state, models);
  }
}

/// Lists [limit] chats, newest first: the newest ones, or those after [cursor] (a page's `nextCursor`).
class ApiListChatsAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ChatPageDto> {
  final int limit;
  final String? cursor;

  ApiListChatsAction({required this.limit, this.cursor});

  @override
  Future<(AccountClient?, ChatPageDto)> reduce() async {
    final page = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listChats(limit: limit, cursor: cursor),
      ),
    );
    return (state, page);
  }

  @override
  String toString() => 'ApiListChatsAction(limit: $limit, cursor: $cursor)';
}

/// Loads the chat [chatId] with its messages.
class ApiGetChatAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ChatDetailDto> {
  final UuidValue chatId;

  ApiGetChatAction({required this.chatId});

  @override
  Future<(AccountClient?, ChatDetailDto)> reduce() async {
    final chat = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getChat(id: chatId),
      ),
    );
    return (state, chat);
  }

  @override
  String toString() => 'ApiGetChatAction(chatId: $chatId)';
}

/// Creates a chat with [content] as its first message (may be blank with [attachmentId]), and starts the answer.
/// It reads all repositories of the user if [allRepositories], else those of [repositoryIds]; [modelId] `null` uses
/// the user's model. A [temporary] chat is not listed, and is deleted a day after its last message.
class ApiCreateChatAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ChatDetailDto> {
  final String content;
  final UuidValue? attachmentId;
  final bool allRepositories;
  final List<UuidValue> repositoryIds;
  final UuidValue? modelId;
  final bool temporary;

  ApiCreateChatAction({
    required this.content,
    required this.attachmentId,
    required this.allRepositories,
    required this.repositoryIds,
    required this.modelId,
    required this.temporary,
  });

  @override
  Future<(AccountClient?, ChatDetailDto)> reduce() async {
    final chat = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.createChat(
          request: CreateChatRequest(
            content: content,
            attachmentId: attachmentId,
            allRepositories: allRepositories,
            repositoryIds: allRepositories ? const [] : repositoryIds,
            modelId: modelId,
            temporary: temporary,
          ),
        ),
      ),
    );
    return (state, chat);
  }

  @override
  String toString() =>
      'ApiCreateChatAction(attachmentId: $attachmentId, allRepositories: $allRepositories, repositoryIds: $repositoryIds, modelId: $modelId, temporary: $temporary)';
}

/// Renames the chat [chatId] to [title] and lets [modelId] answer in it (`null` uses the user's model).
class ApiUpdateChatAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ChatDto> {
  final UuidValue chatId;
  final String title;
  final UuidValue? modelId;

  ApiUpdateChatAction({required this.chatId, required this.title, required this.modelId});

  @override
  Future<(AccountClient?, ChatDto)> reduce() async {
    final chat = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.updateChat(
          id: chatId,
          request: UpdateChatRequest(title: title, modelId: modelId),
        ),
      ),
    );
    return (state, chat);
  }

  @override
  String toString() => 'ApiUpdateChatAction(chatId: $chatId, modelId: $modelId)';
}

/// Sends [content] (may be blank with [attachmentId]) in the chat and returns the user message and the answer being
/// generated.
class ApiSendMessageAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<MessageDto>> {
  final UuidValue chatId;
  final String content;
  final UuidValue? attachmentId;

  ApiSendMessageAction({required this.chatId, required this.content, required this.attachmentId});

  @override
  Future<(AccountClient?, List<MessageDto>)> reduce() async {
    final messages = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.sendMessage(
          chatId: chatId,
          request: SendMessageRequest(content: content, attachmentId: attachmentId),
        ),
      ),
    );
    return (state, messages);
  }

  @override
  String toString() => 'ApiSendMessageAction(chatId: $chatId, attachmentId: $attachmentId)';
}

/// Uploads [content] as the file [fileName], to send with the next message. The server infers its type from the name.
class ApiUploadAttachmentAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, AttachmentDto> {
  final String fileName;
  final Uint8List content;

  ApiUploadAttachmentAction({required this.fileName, required this.content});

  @override
  Future<(AccountClient?, AttachmentDto)> reduce() async {
    final attachment = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.uploadAttachment(fileName: fileName, content: content),
      ),
    );
    return (state, attachment);
  }

  @override
  String toString() => 'ApiUploadAttachmentAction(${content.length} bytes)';
}

/// Loads the file of the attachment [attachmentId].
class ApiDownloadAttachmentAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, FileDownload> {
  final UuidValue attachmentId;

  ApiDownloadAttachmentAction({required this.attachmentId});

  @override
  Future<(AccountClient?, FileDownload)> reduce() async {
    final file = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.downloadAttachment(id: attachmentId),
      ),
    );
    return (state, file);
  }

  @override
  String toString() => 'ApiDownloadAttachmentAction($attachmentId)';
}

/// Stops the answer [messageId]. Its stream then ends with the cancelled message.
class ApiCancelMessageAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue chatId;
  final UuidValue messageId;

  ApiCancelMessageAction({required this.chatId, required this.messageId});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.cancelMessage(chatId: chatId, messageId: messageId),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiCancelMessageAction(messageId: $messageId)';
}

/// Subscribes to the events of the message [messageId], see [MessageEvent].
/// Returns once the server accepted the request; the stream ends after `Done` or `Error`, or when [cancel] is cancelled.
class ApiStreamMessageAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, Stream<MessageEvent>> {
  final UuidValue chatId;
  final UuidValue messageId;
  final CancellationToken cancel;

  ApiStreamMessageAction({required this.chatId, required this.messageId, required this.cancel});

  @override
  Future<(AccountClient?, Stream<MessageEvent>)> reduce() async {
    final events = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.streamMessage(chatId: chatId, messageId: messageId, cancel: cancel),
      ),
    );
    return (state, events);
  }

  @override
  String toString() => 'ApiStreamMessageAction(messageId: $messageId)';
}

/// Loads the tool call [toolCallId] of the chat [chatId] with its output.
class ApiGetToolCallAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ToolCallDto> {
  final UuidValue chatId;
  final UuidValue toolCallId;

  ApiGetToolCallAction({required this.chatId, required this.toolCallId});

  @override
  Future<(AccountClient?, ToolCallDto)> reduce() async {
    final toolCall = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getToolCall(chatId: chatId, toolCallId: toolCallId),
      ),
    );
    return (state, toolCall);
  }

  @override
  String toString() => 'ApiGetToolCallAction(toolCallId: $toolCallId)';
}

/// Loads the file the `present_file_to_user` call [toolCallId] presented, as it is at the call's commit.
class ApiGetPresentedFileAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, FileDownload> {
  final UuidValue chatId;
  final UuidValue toolCallId;

  ApiGetPresentedFileAction({required this.chatId, required this.toolCallId});

  @override
  Future<(AccountClient?, FileDownload)> reduce() async {
    final file = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getPresentedFile(chatId: chatId, toolCallId: toolCallId),
      ),
    );
    return (state, file);
  }

  @override
  String toString() => 'ApiGetPresentedFileAction(toolCallId: $toolCallId)';
}

/// Loads the commit the tool call [toolCallId] proposed, as it is shown: the diff of its file or its moves.
class ApiGetProposedCommitDiffAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, FileDiffDto> {
  final UuidValue chatId;
  final UuidValue toolCallId;

  ApiGetProposedCommitDiffAction({required this.chatId, required this.toolCallId});

  @override
  Future<(AccountClient?, FileDiffDto)> reduce() async {
    final diff = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getProposedCommitDiff(chatId: chatId, toolCallId: toolCallId),
      ),
    );
    return (state, diff);
  }

  @override
  String toString() => 'ApiGetProposedCommitDiffAction(toolCallId: $toolCallId)';
}

/// Loads the change the tool call [toolCallId] proposed, and whether it was committed.
class ApiGetProposedCommitAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ProposedCommitDto> {
  final UuidValue chatId;
  final UuidValue toolCallId;

  ApiGetProposedCommitAction({required this.chatId, required this.toolCallId});

  @override
  Future<(AccountClient?, ProposedCommitDto)> reduce() async {
    final change = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getProposedCommit(chatId: chatId, toolCallId: toolCallId),
      ),
    );
    return (state, change);
  }

  @override
  String toString() => 'ApiGetProposedCommitAction(toolCallId: $toolCallId)';
}

/// Pushes the change the tool call [toolCallId] proposed to the repository's branch.
/// Returns the change with the outcome, `CONFLICT` or `FAILED` with its `error` if it was not pushed.
class ApiCommitProposedCommitAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ProposedCommitDto> {
  final UuidValue chatId;
  final UuidValue toolCallId;

  ApiCommitProposedCommitAction({required this.chatId, required this.toolCallId});

  @override
  Future<(AccountClient?, ProposedCommitDto)> reduce() async {
    final change = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.commitProposedCommit(chatId: chatId, toolCallId: toolCallId),
      ),
    );
    return (state, change);
  }

  @override
  String toString() => 'ApiCommitProposedCommitAction(toolCallId: $toolCallId)';
}
