import 'package:app/config/theme.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/app_drawer.dart';
import 'package:app/widget/chat/assistant_message.dart';
import 'package:app/widget/chat/input_options_sheet.dart';
import 'package:app/widget/chat/instance_hero.dart';
import 'package:app/widget/chat/leave_temporary_dialog.dart';
import 'package:app/widget/chat/mcp_server_sheet.dart';
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
            // A new chat chooses its repositories in the message input.
            title: chat == null ? null : Text(chat.title, overflow: TextOverflow.ellipsis),
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
                        if (await LeaveTemporaryDialog.confirm(context) && context.mounted) {
                          await context.redux(chatProvider).dispatchAsync(NewChatAction());
                        }
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
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: state.messages.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 24),
                          itemBuilder: (context, index) {
                            final message = state.messages[state.messages.length - 1 - index];
                            return switch (message.role) {
                              MessageRole.user => UserMessage(key: ValueKey(message.id), message: message),
                              MessageRole.assistant => _Answer(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An answer, while it is generated as the [MessageService] follows it, so that its events rebuild only this answer.
/// The same widget before and after it finishes, so that the [AssistantMessage] keeps its state (the text it reveals).
class _Answer extends StatelessWidget {
  final UuidValue chatId;

  /// The answer as the chat has it, shown until the [MessageService] follows it, and once it is finished.
  final MessageDto message;
  final String? modelName;

  const _Answer({super.key, required this.chatId, required this.message, required this.modelName});

  @override
  Widget build(BuildContext context) {
    final running = context.watch(messageProvider.select((m) => m != null && m.id == message.id ? m : null));
    return AssistantMessage(
      chatId: chatId,
      message: running != null && message.status == MessageStatus.generating ? running : message,
      modelName: modelName,
    );
  }
}

/// The text field and below it the actions, in one box: a plus button with the options of a new chat (or, without
/// options to choose, a button that attaches a file), the model, and the button that sends the message, or stops the
/// answer being generated. The attached file is above the text field, the repositories and MCP servers of the new chat
/// (unless all) above the plus button.
class _MessageInput extends StatefulWidget {
  const _MessageInput();

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> with Refena {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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

  Future<void> _showOptions() async {
    final option = await InputOptionsSheet.show(context);
    if (!mounted) {
      return;
    }
    switch (option) {
      case InputOption.attach:
        await _attach();
      case InputOption.repositories:
        await RepositorySheet.show(context);
      case InputOption.mcpServers:
        await McpServerSheet.show(context);
      case null:
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final answering = state.answer != null;
    final canSend = state.canSend(_controller.text);
    final attachment = state.attachment;
    final idle = !state.loading && !state.sending;
    // A new chat has options to choose; assumed while it loads, so the attach button does not turn into the plus.
    final options = state.chat == null && !state.loading && (!state.loaded || state.repositories.isNotEmpty || state.mcpServers.isNotEmpty);
    // Only the scopes that are not all items, so the default takes no space.
    final newChat = state.chat == null && state.loaded;
    final chips = [
      if (newChat && state.repositories.isNotEmpty && !state.allRepositories)
        _ScopeChip(
          key: const ValueKey('chat.repositories'),
          icon: RepositorySheet.icon(state),
          label: RepositorySheet.summary(context, state),
          tooltip: context.t.base.repositories.title,
          enabled: idle,
          onPressed: () async => RepositorySheet.show(context),
          onDeleted: () => ref.redux(chatProvider).dispatch(SetRepositoryScopeAction(all: true, ids: const [])),
        ),
      if (newChat && state.mcpServers.isNotEmpty && !state.allMcpServers)
        _ScopeChip(
          key: const ValueKey('chat.mcpServers'),
          icon: McpServerSheet.icon(state),
          label: McpServerSheet.summary(context, state),
          tooltip: context.t.base.mcpServers.title,
          enabled: idle,
          onPressed: () async => McpServerSheet.show(context),
          onDeleted: () => ref.redux(chatProvider).dispatch(SetMcpServerScopeAction(all: true, ids: const [])),
        ),
    ];
    final colors = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: AnimatedContainer(
        // Fades with the page's background.
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          // A shade darker than the page's background,
          // but white on the light temporary background, which is about as dark.
          color: state.isTemporary && colors.brightness == Brightness.light ? colors.surfaceContainerLowest : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _AttachmentChip(attachment: attachment, enabled: !state.sending),
              ),
            TextField(
              key: const ValueKey('chat.input'),
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t.base.chat.placeholder,
                border: InputBorder.none,
                // Lines up with the icon of the button below.
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              ),
            ),
            // Above the plus button, so the model has the rest of the row below.
            if (chips.isNotEmpty)
              GestureDetector(
                // Taps on the free space focus the text field, as if the box were the field.
                behavior: HitTestBehavior.opaque,
                onTap: _focusNode.requestFocus,
                child: Padding(
                  // As far from the edge as the buttons below.
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, children: chips),
                  ),
                ),
              ),
            // The buttons are as far from the edges as from the bottom.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Row(
                children: [
                  if (options)
                    IconButton(
                      key: const ValueKey('chat.options'),
                      icon: const Icon(Icons.add),
                      tooltip: context.t.base.chat.messageInput.options,
                      onPressed: idle && state.loaded ? _showOptions : null,
                    )
                  else
                    IconButton(
                      key: const ValueKey('chat.attach'),
                      icon: const Icon(Icons.attach_file),
                      tooltip: context.t.base.chat.messageInput.attach,
                      onPressed: idle ? _attach : null,
                    ),
                  Expanded(
                    // Taps on the free space focus the text field, as if the box were the field.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _focusNode.requestFocus,
                      // The model next to the send button, as wide as its name, up to all of the space.
                      child: SizedBox(
                        height: 48,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: state.models.isEmpty ? null : _ModelButton(state: state, enabled: idle),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Stopping keeps the keyboard open, sending closes it.
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

/// A scope of the new chat while it is not all items, opening the sheet to choose them. Removing it chooses all again.
class _ScopeChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// What the items are, e.g. "Repositories".
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback onDeleted;

  const _ScopeChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      isEnabled: enabled,
      avatar: Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      tooltip: tooltip,
      onPressed: onPressed,
      onDeleted: onDeleted,
    );
  }
}

/// The model that answers in the chat, as quiet text next to the send button, opening a sheet to choose another.
class _ModelButton extends StatelessWidget {
  final ChatState state;
  final bool enabled;

  const _ModelButton({required this.state, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final defaultModelId = context.watch(meProvider.select((user) => user?.defaultModelId));
    return TextButton(
      key: const ValueKey('chat.model'),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: enabled ? () async => ModelSheet.show(context) : null,
      child: Text(
        state.answeringModel(defaultModelId)?.displayName ?? context.t.base.common.kDefault,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
