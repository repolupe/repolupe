import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/presented_file_page.dart';
import 'package:app/pages/proposed_commit_page.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/util/tool_call.dart';
import 'package:app/widget/chat/markdown_content.dart';
import 'package:app/widget/chat/smooth_text.dart';
import 'package:app/widget/chat/tool_call_list.dart';
import 'package:app/widget/chat/usage_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// An answer, with the tools it used above it, and below it the files the model showed and the changes it proposed
/// (each opening a page), the model that wrote it, how long it took and what it cost (like the web's).
class AssistantMessage extends StatefulWidget {
  final UuidValue chatId;
  final MessageDto message;

  /// The model that wrote the answer, if it still exists.
  final String? modelName;

  const AssistantMessage({super.key, required this.chatId, required this.message, required this.modelName});

  @override
  State<AssistantMessage> createState() => _AssistantMessageState();
}

class _AssistantMessageState extends State<AssistantMessage> {
  /// Ticks every second while generating, so the duration counts up.
  Timer? _timer;

  bool get _generating => widget.message.status == MessageStatus.generating;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(AssistantMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTimer() {
    if (_generating) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// How long the answer took (or has taken so far), unknown if it was interrupted by a restart.
  String? get _duration {
    final end = _generating ? DateTime.now() : widget.message.finishedAt;
    if (end == null) {
      return null;
    }
    final duration = end.difference(widget.message.createdAt);
    // Clamped, as the device's clock may be behind the server's.
    return formatDuration(duration.isNegative ? Duration.zero : duration);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final caption = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // Shown only once the answer is complete, not while generating or after it failed or was cancelled.
    final completed = message.status == MessageStatus.completed;
    final files = completed ? presentedFiles(message) : const <ToolCallFile>[];
    final changes = completed ? proposedChanges(message) : const <ToolCallFile>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.toolCalls.isNotEmpty) ...[
            ToolCallList(chatId: widget.chatId, messageId: message.id, toolCalls: message.toolCalls),
            const SizedBox(height: 8),
          ],

          // Streamed text is revealed smoothly rather than in the batches it arrives in. Kept while the answer has no
          // text yet, so that its first batch is revealed too.
          SmoothText(
            text: message.content,
            builder: (context, content, revealing) {
              if (message.content.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarkdownContent(content: content),
                    if (_generating || revealing) ...[
                      const SizedBox(height: 12),
                      const _Spinner(),
                    ],
                  ],
                );
              }
              if (_generating) {
                return Row(
                  children: [
                    const _Spinner(),
                    const SizedBox(width: 8),
                    Text(context.t.base.chat.assistantMessage.thinking, style: muted),
                  ],
                );
              }
              if (completed && files.isEmpty && changes.isEmpty) {
                return Text(context.t.base.chat.assistantMessage.noAnswer, style: muted);
              }
              return const SizedBox.shrink();
            },
          ),

          if (files.isNotEmpty || changes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final change in changes) _ChangeButton(chatId: widget.chatId, change: change),
                for (final file in files) _FileButton(chatId: widget.chatId, file: file),
              ],
            ),
          ],

          if (message.status == MessageStatus.failed) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message.error ?? context.t.base.chat.assistantMessage.failed,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],

          if (message.status == MessageStatus.cancelled) ...[
            const SizedBox(height: 12),
            _IconText(icon: Icons.cancel_outlined, text: context.t.base.chat.assistantMessage.cancelled, style: caption),
          ],

          _Footer(message: message, modelName: widget.modelName, duration: _duration, style: caption),
        ],
      ),
    );
  }
}

/// Opens the diff of a change the model proposed.
class _ChangeButton extends StatelessWidget {
  final UuidValue chatId;
  final ToolCallFile change;

  const _ChangeButton({required this.chatId, required this.change});

  @override
  Widget build(BuildContext context) {
    final moves = change.toolCall.moves;
    final ref = context.ref;
    return FilledButton.tonalIcon(
      icon: Icon(change.toolCall.icon),
      label: Text(moves.length > 1 ? context.t.base.chat.moveCount(count: moves.length) : fileName(change.path), overflow: TextOverflow.ellipsis),
      onPressed: () async {
        await ref.global.dispatchAsync(NavigateAction.push(ProposedCommitPage(chatId: chatId, toolCall: change.toolCall, path: change.path)));
      },
    );
  }
}

/// Opens a file the model showed.
class _FileButton extends StatelessWidget {
  final UuidValue chatId;
  final ToolCallFile file;

  const _FileButton({required this.chatId, required this.file});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    return FilledButton.tonalIcon(
      icon: const Icon(Icons.description_outlined),
      label: Text(fileName(file.path), overflow: TextOverflow.ellipsis),
      onPressed: () async {
        await ref.global.dispatchAsync(NavigateAction.push(PresentedFilePage(chatId: chatId, toolCall: file.toolCall, path: file.path)));
      },
    );
  }
}

/// On a phone one line that never wraps: the model on the left (cut off when too long, in full on long press), the
/// duration and the cost on the right. Otherwise all of it on the left, wrapping when too long (like the web's).
/// Tapping the cost shows the token usage.
class _Footer extends StatelessWidget {
  final MessageDto message;
  final String? modelName;
  final String? duration;
  final TextStyle? style;

  const _Footer({required this.message, required this.modelName, required this.duration, required this.style});

  @override
  Widget build(BuildContext context) {
    final modelName = this.modelName;
    final duration = this.duration;
    final cost = message.cost;
    final usage = message.usage;
    if (modelName == null && duration == null && cost == null) {
      return const SizedBox.shrink();
    }

    final style = this.style?.copyWith(letterSpacing: 0.2);
    final tabular = style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    // A cost is only computed from a usage, so an answer with one always has the other.
    final costLink = switch ((cost, usage)) {
      (final cost?, final usage?) => GestureDetector(
        key: ValueKey('chat.message.${message.id}.cost'),
        behavior: HitTestBehavior.opaque,
        onTap: () => UsageSheet.show(context, usage: usage, cost: cost, modelName: modelName),
        child: Text(formatCost(cost.amount, cost.currency), style: tabular),
      ),
      _ => null,
    };
    final separator = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('·', style: style),
    );

    // the web's xs breakpoint
    if (MediaQuery.sizeOf(context).width >= 600) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (modelName != null) _IconText(icon: Icons.smart_toy_outlined, text: modelName, style: style, truncate: false),
            if (modelName != null && (duration != null || costLink != null)) separator,
            if (duration != null) Text(duration, style: tabular),
            if (duration != null && costLink != null) separator,
            ?costLink,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          if (modelName != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: modelName,
                  child: _IconText(icon: Icons.smart_toy_outlined, text: modelName, style: style),
                ),
              ),
            )
          else
            const Spacer(),
          if (duration != null) ...[
            const SizedBox(width: 12),
            Text(duration, style: tabular),
          ],
          if (costLink != null) ...[
            if (duration != null) separator else const SizedBox(width: 12),
            costLink,
          ],
        ],
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle? style;

  /// Cut off at the end of the line, or wrapped.
  final bool truncate;

  const _IconText({required this.icon, required this.text, required this.style, this.truncate = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: 4),
        Flexible(
          child: truncate ? Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis) : Text(text, style: style),
        ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
