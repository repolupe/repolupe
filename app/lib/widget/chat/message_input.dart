import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/chat/input_options_sheet.dart';
import 'package:app/widget/chat/mcp_server_sheet.dart';
import 'package:app/widget/chat/model_sheet.dart';
import 'package:app/widget/chat/repository_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The text field and below it the actions, in one box: a plus button with the options of a new chat (or, without
/// options to choose, a button that attaches a file), the model, and the button that sends the message, or stops the
/// answer being generated. The attached file is above the text field, the repositories and MCP servers of the new chat
/// (unless all) above the plus button.
class MessageInput extends StatefulWidget {
  const MessageInput({super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> with Refena {
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
          mainAxisSize: MainAxisSize.min,
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
                    IconButton(
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
