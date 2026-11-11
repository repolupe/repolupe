import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/attachment_page.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/attachment_label.dart';
import 'package:app/widget/chat/edit_message_sheet.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum _MessageAction { edit, retry }

/// A message the user sent, on the right, with the file attached to it above. The text may be blank then.
/// A long press offers to edit it or to send it again, unless an answer is being generated.
class UserMessage extends StatelessWidget {
  final MessageDto message;

  const UserMessage({super.key, required this.message});

  /// Shows the actions where the user pressed, at the global [position], and carries out the chosen one.
  Future<void> _showActions(BuildContext context, Offset position) async {
    final t = context.t;
    final ref = context.ref;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    unawaited(Feedback.forLongPress(context));
    final action = await showMenu<_MessageAction>(
      context: context,
      position: RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          key: ValueKey('chat.message.${message.id}.edit'),
          value: _MessageAction.edit,
          child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t.base.common.edit), contentPadding: EdgeInsets.zero),
        ),
        PopupMenuItem(
          key: ValueKey('chat.message.${message.id}.retry'),
          value: _MessageAction.retry,
          child: ListTile(leading: const Icon(Icons.refresh), title: Text(t.base.common.retry), contentPadding: EdgeInsets.zero),
        ),
      ],
    );
    if (action == null || !context.mounted) {
      return;
    }

    switch (action) {
      case _MessageAction.edit:
        await EditMessageSheet.show(context, message: message);
      case _MessageAction.retry:
        final chats = ref.redux(chatProvider);
        if (ref.read(chatProvider).resendRemovesLater(message.id)) {
          // More than its answer would be gone.
          await ConfirmDialog.show(
            context,
            title: t.base.chat.retryMessageDialog.title,
            text: t.base.chat.retryMessageDialog.text,
            confirmText: t.base.common.retry,
            confirmIcon: Icons.refresh,
            confirmKey: 'chat.retryMessage.confirm',
            onConfirm: () => chats.dispatchAsyncTakeResult(ResendMessageAction(message.id)),
          );
        } else {
          final error = await chats.dispatchAsyncTakeResult(ResendMessageAction(message.id));
          if (error != null) {
            ref.global.dispatch(ShowSnackBarAction(message: error));
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = context.ref;
    final attachment = message.attachment;
    final canResend = context.watch(chatProvider.select((state) => state.canResend));
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
          child: GestureDetector(
            key: ValueKey('chat.message.${message.id}.user'),
            onLongPressStart: canResend ? (details) => _showActions(context, details.globalPosition) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 8,
              children: [
                if (attachment != null)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.attach_file),
                    label: AttachmentLabel(
                      fileName: attachment.fileName,
                      size: attachment.size,
                      sizeColor: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                    ),
                    onPressed: () async {
                      await ref.global.dispatchAsync(NavigateAction.push(AttachmentPage(attachment: attachment)));
                    },
                  ),
                if (message.content.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      message.content,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
