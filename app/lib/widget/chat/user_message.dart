import 'package:app/pages/attachment_page.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// A message the user sent, on the right, with the file attached to it above. The text may be blank then.
class UserMessage extends StatelessWidget {
  final MessageDto message;

  const UserMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = context.ref;
    final attachment = message.attachment;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 8,
            children: [
              if (attachment != null)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.attach_file),
                  label: Text.rich(
                    TextSpan(
                      text: attachment.fileName,
                      children: [
                        TextSpan(
                          text: '  ${formatBytes(attachment.size)}',
                          style: TextStyle(color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
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
                  child: SelectableText(
                    message.content,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
