import 'package:app/gen/strings.g.dart';
import 'package:app/pages/tool_call_page.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/tool_call.dart';
import 'package:app/widget/chat/tool_call_info.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// E.g. "Used 3 tools (1 failed)", or "Reading the repositories" while one is running.
String _summary(BuildContext context, List<ToolCallSummaryDto> toolCalls) {
  final texts = context.t.base.chat.toolCallList;
  if (toolCalls.any((t) => t.status == ToolCallStatus.running)) {
    return texts.running;
  }
  final count = toolCalls.length;
  final failed = toolCalls.where((t) => t.status == ToolCallStatus.failed).length;
  return failed > 0 ? texts.usedWithFailed(count: count, failed: failed) : texts.used(count: count);
}

/// The tool calls of an answer, collapsed into how many there were; tapping it lists them in a [ToolCallSheet].
class ToolCallList extends StatelessWidget {
  final UuidValue chatId;
  final UuidValue messageId;
  final List<ToolCallSummaryDto> toolCalls;

  const ToolCallList({super.key, required this.chatId, required this.messageId, required this.toolCalls});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final running = toolCalls.any((t) => t.status == ToolCallStatus.running);

    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: muted,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => ToolCallSheet.show(context, chatId: chatId, messageId: messageId, toolCalls: toolCalls),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running) const ToolCallStatusIcon(status: ToolCallStatus.running) else Icon(Icons.handyman_outlined, size: 16, color: muted),
          const SizedBox(width: 8),
          Text(_summary(context, toolCalls)),
        ],
      ),
    );
  }
}

/// The tool calls of an answer, updated while it is generating. Tapping one opens its input and output.
class ToolCallSheet extends StatelessWidget {
  final UuidValue chatId;
  final UuidValue messageId;

  /// The tool calls when the sheet was opened, shown if the answer is neither followed nor in the chat anymore.
  final List<ToolCallSummaryDto> toolCalls;

  const ToolCallSheet({super.key, required this.chatId, required this.messageId, required this.toolCalls});

  static Future<void> show(
    BuildContext context, {
    required UuidValue chatId,
    required UuidValue messageId,
    required List<ToolCallSummaryDto> toolCalls,
  }) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => ToolCallSheet(chatId: chatId, messageId: messageId, toolCalls: toolCalls),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The answer being generated as the MessageService follows it, else as the chat has it.
    final running = context.watch(messageProvider.select((m) => m != null && m.id == messageId ? m.toolCalls : null));
    final finished = context.watch(chatProvider.select((s) => s.messages.where((m) => m.id == messageId).firstOrNull?.toolCalls));
    final toolCalls = running ?? finished ?? this.toolCalls;
    final ref = context.ref;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_summary(context, toolCalls), style: theme.textTheme.titleSmall),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final toolCall in toolCalls)
                  ListTile(
                    title: ToolCallLabel(toolCall: toolCall),
                    trailing: ToolCallStatusIcon(status: toolCall.status),
                    onTap: () async {
                      await ref.global.dispatchAsync(NavigateAction.push(ToolCallPage(chatId: chatId, toolCall: toolCall)));
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The tool's icon and name, followed by the most telling part of its input, in one line.
class ToolCallLabel extends StatelessWidget {
  final ToolCallSummaryDto toolCall;

  const ToolCallLabel({super.key, required this.toolCall});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']);
    final detail = toolCall.detail;
    return Row(
      children: [
        Icon(toolCall.icon, size: 16),
        const SizedBox(width: 8),
        Text(toolCall.name, style: mono?.copyWith(fontWeight: FontWeight.w600)),
        if (detail.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}
