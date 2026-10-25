import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/app_drawer.dart';
import 'package:app/widget/chat/assistant_message.dart';
import 'package:app/widget/chat/instance_hero.dart';
import 'package:app/widget/chat/model_sheet.dart';
import 'package:app/widget/chat/repository_sheet.dart';
import 'package:app/widget/chat/user_message.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// A chat with the model of the active account, a new one every time the page opens.
/// The drawer lists the previous chats to open instead, and the accounts.
class ChatPage extends StatefulWidget {
  /// The repositories the new chat reads instead of all of them, e.g. opened from a repository's page.
  final List<UuidValue>? repositoryIds;

  const ChatPage({super.key, this.repositoryIds});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with Refena {
  @override
  void initState() {
    super.initState();
    // The page opens again when the account changes.
    ensureRef((ref) {
      ref.redux(chatListProvider).dispatch(ClearChatsAction());
      // ignore: discarded_futures
      ref.redux(chatProvider).dispatchAsync(NewChatAction(repositoryIds: widget.repositoryIds));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final chat = state.chat;
    return Scaffold(
      drawer: const AppDrawer(),
      onDrawerChanged: (opened) async {
        if (opened) {
          await ref.redux(chatListProvider).dispatchAsync(LoadChatsAction(limit: 10));
        }
      },
      appBar: AppBar(
        leading: Builder(
          // Below the Scaffold, to find it.
          builder: (context) => IconButton(
            key: const ValueKey('chat.drawer'),
            icon: const Icon(Icons.menu),
            tooltip: context.t.base.chat.title,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: switch (state.chat) {
          final chat? => Text(chat.title, overflow: TextOverflow.ellipsis),
          null => const _RepositoryButton(),
        },
        actions: [
          if (chat == null)
            IconButton(
              key: const ValueKey('chat.temporary'),
              icon: Icon(state.isTemporary ? Icons.close : Icons.history_toggle_off),
              tooltip: state.temporary ? context.t.flutter.chat.page.temporaryOff : context.t.base.chat.temporary,
              onPressed: state.loading || state.sending
                  ? null
                  : () {
                      context.redux(chatProvider).dispatch(SetTemporaryAction(!state.temporary));
                    },
            ),
          IconButton(
            key: const ValueKey('chat.newChat'),
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: context.t.base.app.navigation.newChat,
            onPressed: state.messages.isEmpty
                ? null
                : () async {
                    await context.redux(chatProvider).dispatchAsync(NewChatAction());
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Expanded(
                  child: state.loading
                      ? const Center(child: CircularProgressIndicator())
                      : chat == null || state.messages.isEmpty
                      ? InstanceHero(temporary: state.isTemporary)
                      : ListView.separated(
                          key: const ValueKey('chat.messages'),
                          // Starts at the bottom and stays there while the answer grows.
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: state.messages.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final message = state.messages[state.messages.length - 1 - index];
                            return switch (message.role) {
                              MessageRole.user => UserMessage(key: ValueKey(message.id), message: message),
                              MessageRole.assistant when message.status == MessageStatus.generating => _RunningAnswer(
                                key: ValueKey(message.id),
                                chatId: chat.id,
                                message: message,
                                modelName: state.modelName(message.modelId),
                              ),
                              MessageRole.assistant => AssistantMessage(
                                key: ValueKey(message.id),
                                chatId: chat.id,
                                message: message,
                                modelName: state.modelName(message.modelId),
                              ),
                            };
                          },
                        ),
                ),
                const _MessageInput(),
                const _ModelButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The answer being generated, as the [MessageService] follows it, so that its events rebuild only this answer.
class _RunningAnswer extends StatelessWidget {
  final UuidValue chatId;

  /// The answer as the chat has it, shown until the [MessageService] follows it.
  final MessageDto message;
  final String? modelName;

  const _RunningAnswer({super.key, required this.chatId, required this.message, required this.modelName});

  @override
  Widget build(BuildContext context) {
    final running = context.watch(messageProvider);
    return AssistantMessage(
      chatId: chatId,
      message: running != null && running.id == message.id ? running : message,
      modelName: modelName,
    );
  }
}

/// The text field and the button that sends the message, or stops the answer being generated.
class _MessageInput extends StatefulWidget {
  const _MessageInput();

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> with Refena {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await ref.redux(chatProvider).dispatchAsyncTakeResult(SendMessageAction(_controller.text));
    if (sent && mounted) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final answering = state.answer != null;
    final canSend = !state.sending && !answering && _controller.text.trim().isNotEmpty;
    // Sending or stopping keeps the keyboard open.
    return TextFieldTapRegion(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        decoration: BoxDecoration(
          // A shade darker than the answers' surfaceContainerLow.
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('chat.input'),
                controller: _controller,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.t.base.chat.placeholder,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (answering)
              IconButton.filledTonal(
                key: const ValueKey('chat.stop'),
                icon: const Icon(Icons.stop),
                tooltip: context.t.base.chat.messageInput.stop,
                onPressed: () async {
                  await ref.redux(chatProvider).dispatchAsync(CancelAnswerAction());
                },
              )
            else
              IconButton.filled(
                key: const ValueKey('chat.send'),
                icon: state.sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                tooltip: context.t.base.chat.messageInput.send,
                onPressed: canSend ? _send : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// The title of a new chat: the repositories it reads, opening a sheet to choose them.
/// Just "New chat" while the user has none.
class _RepositoryButton extends StatelessWidget {
  const _RepositoryButton();

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    if (state.repositories.isEmpty) {
      return Text(state.loading ? '' : context.t.base.app.navigation.newChat);
    }
    return TextButton.icon(
      icon: const Icon(Icons.folder_outlined),
      label: Text(RepositorySheet.summary(context, state), overflow: TextOverflow.ellipsis),
      onPressed: !state.loading && !state.sending ? () async => RepositorySheet.show(context) : null,
    );
  }
}

/// The model that answers in the chat, opening a sheet to choose another.
/// Hidden while there are none to choose.
class _ModelButton extends StatelessWidget {
  const _ModelButton();

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    if (state.models.isEmpty) {
      // The space below the input.
      return const SizedBox(height: 16);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.smart_toy_outlined),
          label: Text(state.answeringModel?.displayName ?? context.t.base.common.kDefault, overflow: TextOverflow.ellipsis),
          onPressed: !state.loading && !state.sending ? () async => ModelSheet.show(context) : null,
        ),
      ),
    );
  }
}
