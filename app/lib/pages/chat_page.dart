import 'package:app/config/theme.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/app_drawer.dart';
import 'package:app/widget/chat/assistant_message.dart';
import 'package:app/widget/chat/instance_hero.dart';
import 'package:app/widget/chat/model_sheet.dart';
import 'package:app/widget/chat/repository_sheet.dart';
import 'package:app/widget/chat/user_message.dart';
import 'package:file_picker/file_picker.dart';
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
    // Fades to the temporary background, the app bar too because it has the page's color.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: state.isTemporary ? 1 : 0),
      duration: const Duration(milliseconds: 250),
      builder: (context, temporary, body) {
        final colors = Theme.of(context).colorScheme;
        final background = Color.lerp(colors.surface, colors.temporary, temporary)!;
        final scrolledUnder = Color.lerp(colors.surfaceContainer, colors.temporaryContainer, temporary)!;
        return Scaffold(
          backgroundColor: background,
          drawer: const AppDrawer(),
          onDrawerChanged: (opened) async {
            if (opened) {
              await ref.redux(chatListProvider).dispatchAsync(LoadChatsAction(limit: 10));
            }
          },
          appBar: AppBar(
            backgroundColor: WidgetStateColor.resolveWith(
              (states) => states.contains(WidgetState.scrolledUnder) ? scrolledUnder : background,
            ),
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
          body: body,
        );
      },
      child: SafeArea(
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

/// The text field with the button that attaches a file, the attached one above, and the button that sends the
/// message, or stops the answer being generated.
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
    // Unfocusing the field, not the page's scope, which would keep it as the scope's focused child,
    // so that the scope focusing again (e.g. when the drawer opens) would show the keyboard again.
    FocusManager.instance.primaryFocus?.unfocus();
    final sent = await ref.redux(chatProvider).dispatchAsyncTakeResult(SendMessageAction(_controller.text));
    if (sent && mounted) {
      _controller.clear();
    }
  }

  Future<void> _attach() async {
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) {
      return;
    }
    // Without a length, reading the file fails too, which the action reports.
    final size = file.lengthSync() ?? await file.length() ?? 0;
    await ref.redux(chatProvider).dispatchAsync(AttachFileAction(fileName: file.name, size: size, read: file.readAsBytes));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final answering = state.answer != null;
    final canSend = state.canSend(_controller.text);
    final attachment = state.attachment;
    // Stopping keeps the keyboard open, sending closes it.
    final colors = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: AnimatedContainer(
        // Fades with the page's background.
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          // A shade darker than the answers' surfaceContainerLow,
          // but white on the light temporary background, which is about as dark.
          color: state.isTemporary && colors.brightness == Brightness.light ? colors.surfaceContainerLowest : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: _AttachmentChip(attachment: attachment, enabled: !state.sending),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('chat.attach'),
                  icon: const Icon(Icons.attach_file),
                  tooltip: context.t.flutter.chat.messageInput.attach,
                  onPressed: state.loading || state.sending ? null : _attach,
                ),
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
          ],
        ),
      ),
    );
  }
}

/// The file attached to the next message, with a spinner while it is uploaded, and a button that removes it.
class _AttachmentChip extends StatelessWidget {
  final PendingAttachment attachment;
  final bool enabled;

  const _AttachmentChip({required this.attachment, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputChip(
      key: const ValueKey('chat.attachment'),
      isEnabled: enabled,
      avatar: attachment.uploaded == null
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.attach_file),
      label: Text.rich(
        TextSpan(
          text: attachment.fileName,
          children: [
            TextSpan(
              text: '  ${formatBytes(attachment.size)}',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: () => context.redux(chatProvider).dispatch(RemoveAttachmentAction()),
    );
  }
}

/// The title of a new chat: the repositories it reads, opening a sheet to choose them.
/// Just "New chat" while the user has none. Fades in once the repositories are loaded.
class _RepositoryButton extends StatelessWidget {
  const _RepositoryButton();

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (state) {
        ChatState(loaded: false) || ChatState(loading: true, repositories: []) => const SizedBox.shrink(),
        ChatState(repositories: []) => Text(context.t.base.app.navigation.newChat),
        _ => TextButton.icon(
          icon: const Icon(Icons.folder_outlined),
          label: Text(RepositorySheet.summary(context, state), overflow: TextOverflow.ellipsis),
          onPressed: !state.loading && !state.sending ? () async => RepositorySheet.show(context) : null,
        ),
      },
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
