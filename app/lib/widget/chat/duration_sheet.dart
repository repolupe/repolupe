import 'dart:async';
import 'dart:math';

import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/util/tool_call.dart';
import 'package:app/widget/chat/answer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The finished calls of one tool of an answer.
typedef _ToolDuration = ({
  /// The full name, e.g. `mcp__github__search`.
  String name,

  /// As shown: a tool of an MCP server without its server.
  String label,
  String? server,
  int count,
  int ms,
});

/// The finished calls of [toolCalls] grouped by tool, the longest first, then the most called. Running ones join once
/// they finish.
List<_ToolDuration> _toolDurations(List<ToolCallSummaryDto> toolCalls) {
  final byName = <String, _ToolDuration>{};
  for (final toolCall in toolCalls) {
    final ms = toolCall.durationMs;
    if (ms == null) {
      continue;
    }
    final mcp = parseMcpToolName(toolCall.name);
    final tool = byName[toolCall.name] ?? (name: toolCall.name, label: mcp?.tool ?? toolCall.name, server: mcp?.server, count: 0, ms: 0);
    byName[toolCall.name] = (name: tool.name, label: tool.label, server: tool.server, count: tool.count + 1, ms: tool.ms + ms);
  }
  return byName.values.toList()..sort((a, b) {
    final byMs = b.ms.compareTo(a.ms);
    final byCount = byMs != 0 ? byMs : b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
}

/// How long at least one tool was running in milliseconds: the union of the runs of the finished [toolCalls]. A call
/// starts right after it was created, the server only stores the other calls of the same response in between.
int _toolsRealMs(List<ToolCallSummaryDto> toolCalls) {
  final runs = [
    for (final toolCall in toolCalls)
      if (toolCall.durationMs case final ms?) (start: toolCall.createdAt.millisecondsSinceEpoch, ms: ms),
  ]..sort((a, b) => a.start.compareTo(b.start));
  var total = 0;
  int? coveredUntil;
  for (final run in runs) {
    final end = run.start + run.ms;
    total += max(0, end - max(run.start, coveredUntil ?? run.start));
    coveredUntil = max(coveredUntil ?? end, end);
  }
  return total;
}

/// How long an answer took: its language model with its output speed, its tools by name, and the total (like the
/// web's duration dialog). Updated while the answer is generating.
class DurationSheet extends StatelessWidget {
  /// The answer when the sheet was opened, shown if it is neither followed nor in the chat anymore.
  final MessageDto message;

  const DurationSheet({super.key, required this.message});

  static Future<void> show(BuildContext context, {required MessageDto message}) async {
    await AnswerSheet.show(context, builder: (_) => DurationSheet(message: message));
  }

  @override
  Widget build(BuildContext context) {
    // The answer being generated as the MessageService follows it, else as the chat has it.
    final id = message.id;
    final running = context.watch(messageProvider.select((m) => m != null && m.id == id ? m : null));
    final finished = context.watch(chatProvider.select((s) => s.messages.where((m) => m.id == id).firstOrNull));
    return _DurationTable(message: running ?? finished ?? message);
  }
}

class _DurationTable extends StatefulWidget {
  final MessageDto message;

  const _DurationTable({required this.message});

  @override
  State<_DurationTable> createState() => _DurationTableState();
}

class _DurationTableState extends State<_DurationTable> {
  /// Ticks while generating, so the total runs like a stopwatch.
  Timer? _timer;

  bool get _generating => widget.message.status == MessageStatus.generating;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(_DurationTable oldWidget) {
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
      _timer ??= Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Like the duration below the answer, unknown if it was interrupted by a restart.
  int? get _totalMs {
    final end = _generating ? DateTime.now() : widget.message.finishedAt;
    if (end == null) {
      return null;
    }
    // Clamped, as the device's clock may be behind the server's.
    return max(0, end.difference(widget.message.createdAt).inMilliseconds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = context.t.base.chat.durationDialog;
    final message = widget.message;
    final muted = theme.colorScheme.onSurfaceVariant;
    final tabular = theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final strong = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(color: muted);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']);

    final totalMs = _totalMs;
    final responseMs = message.responseMs;
    // Output tokens per second of the responses so far, unknown before the first.
    final outputTokens = message.usage?.outputTokens;
    final speed = outputTokens != null && responseMs != null && responseMs > 0 ? outputTokens / (responseMs / 1000) : null;
    final tools = _toolDurations(message.toolCalls);

    return AnswerSheet(
      key: const ValueKey('chat.duration'),
      title: labels.title,
      modelName: message.modelName,
      children: [
        if (responseMs != null) ...[
          _Row(
            label: Text(labels.model),
            value: Text(formatExactDuration(responseMs), style: tabular),
          ),
          if (speed != null)
            _Row(
              label: Text(labels.speed),
              value: Text(labels.tokensPerSecond(speed: formatSpeed(speed)), style: tabular),
            ),
        ],
        if (tools.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(labels.tools, style: theme.textTheme.titleSmall),
          ),
          for (final tool in tools)
            _Row(
              // Wraps between its parts, which have no spaces between them to break at.
              label: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    labels.callCount(count: tool.count),
                    style: tabular?.copyWith(color: muted),
                  ),
                  Text(tool.label, style: mono?.copyWith(fontWeight: FontWeight.w600)),
                  if (tool.server case final server?) Text(server, style: mono?.copyWith(color: muted)),
                ],
              ),
              value: Text(formatExactDuration(tool.ms), style: tabular),
            ),
          _Row(
            label: Text(labels.toolsSum),
            // Can be more than the time the tools took, as calls of the same response run at the same time.
            value: Text(formatExactDuration(tools.fold(0, (sum, tool) => sum + tool.ms)), style: tabular),
          ),
          _Row(
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(labels.toolsReal),
                Text(labels.toolsRealHint, style: hintStyle),
              ],
            ),
            value: Text(formatExactDuration(_toolsRealMs(message.toolCalls)), style: tabular),
          ),
        ],
        if (totalMs != null)
          _Row(
            label: Text(labels.total, style: strong),
            value: Text(formatExactDuration(totalMs), style: tabular?.copyWith(fontWeight: FontWeight.w500)),
            divider: false,
          ),
        if (responseMs == null && !_generating)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(labels.notMeasured, style: hintStyle),
          ),
      ],
    );
  }
}

/// A row of the table, with the value right-aligned and a divider below.
class _Row extends StatelessWidget {
  final Widget label;
  final Widget value;
  final bool divider;

  const _Row({required this.label, required this.value, this.divider = true});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: Theme.of(context).dividerColor)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 16),
            value,
          ],
        ),
      ),
    );
  }
}
