import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/presented_file_page.dart';
import 'package:app/pages/proposed_commit_page.dart';
import 'package:app/pages/raw_answer_page.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/util/markdown.dart';
import 'package:app/util/tool_call.dart';
import 'package:app/widget/animated_number.dart';
import 'package:app/widget/chat/duration_sheet.dart';
import 'package:app/widget/chat/markdown_content.dart';
import 'package:app/widget/chat/smooth_text.dart';
import 'package:app/widget/chat/tool_call_list.dart';
import 'package:app/widget/chat/usage_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// An answer, with the tools it used above it (and right after them its menu, once it is finished), and below it the
/// files the model showed and the changes it proposed (each opening a page), the model that wrote it, how long it took
/// and what it cost (like the web's).
class AssistantMessage extends StatefulWidget {
  final UuidValue chatId;
  final MessageDto message;

  /// The space to the left and right of the content. Wide tables in the answer scroll through it to the edges.
  final double horizontalPadding;

  /// Called right before the answer changes its height on the user's request (when they switch how its tables are laid
  /// out), so that the list can keep its top in place.
  final VoidCallback? onResize;

  const AssistantMessage({
    super.key,
    required this.chatId,
    required this.message,
    this.horizontalPadding = 0,
    this.onResize,
  });

  @override
  State<AssistantMessage> createState() => _AssistantMessageState();
}

class _AssistantMessageState extends State<AssistantMessage> {
  /// Ticks every second while generating, so the duration counts up.
  Timer? _timer;

  /// Whether wide tables scroll sideways rather than fit the width (the default). Kept in the route's [PageStorage], so
  /// that it survives the answer being scrolled out of the list and back.
  bool _scrollTables = false;

  /// The content [_hasTable] was found in, so that it is parsed again only when it changes.
  String? _parsedContent;
  bool _parsedHasTable = false;

  bool get _generating => widget.message.status == MessageStatus.generating;

  Object get _scrollTablesId => ('scrollTables', widget.message.id);

  /// Whether the answer has a table.
  bool get _hasTable {
    final content = widget.message.content;
    if (content != _parsedContent) {
      _parsedContent = content;
      _parsedHasTable = containsTable(content);
    }
    return _parsedHasTable;
  }

  @override
  void initState() {
    super.initState();
    _scrollTables = PageStorage.maybeOf(context)?.readState(context, identifier: _scrollTablesId) as bool? ?? false;
    _updateTimer();
  }

  void _toggleScrollTables() {
    widget.onResize?.call();
    setState(() => _scrollTables = !_scrollTables);
    PageStorage.maybeOf(context)?.writeState(context, _scrollTables, identifier: _scrollTablesId);
  }

  @override
  void didUpdateWidget(AssistantMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTimer();
  }

  /// What the answer is doing while generating: the running tool, or, before it has text, the last one that ran, so
  /// that a brief one doesn't flicker back to "Thinking…". Taken from the calls rather than from the running ones seen
  /// in a build, since a brief call (e.g. `run_script`) often starts and finishes between two frames.
  String? _statusLabel(BuildContext context) {
    if (!_generating) {
      return null;
    }
    final toolCalls = widget.message.toolCalls;
    final running = runningToolName(toolCalls);
    if (running != null) {
      return runningToolLabel(context, running);
    }
    if (widget.message.content.isNotEmpty) {
      return null;
    }
    final last = toolCalls.lastOrNull?.name;
    return last != null ? runningToolLabel(context, last) : context.t.base.chat.assistantMessage.thinking;
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
    final status = _statusLabel(context);
    final padding = EdgeInsets.symmetric(horizontal: widget.horizontalPadding);
    // Offered once the answer is finished, also if it failed or was cancelled.
    final menu = !_generating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.toolCalls.isNotEmpty || menu) ...[
          Padding(
            padding: padding,
            child: Row(
              children: [
                if (message.toolCalls.isNotEmpty) ToolCallList(chatId: widget.chatId, messageId: message.id, toolCalls: message.toolCalls),
                if (menu)
                  _AnswerMenu(
                    chatId: widget.chatId,
                    messageId: message.id,
                    hasTable: _hasTable,
                    scrollTables: _scrollTables,
                    onToggleScrollTables: _toggleScrollTables,
                  ),
              ],
            ),
          ),
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
                  MarkdownContent(
                    content: content,
                    horizontalPadding: widget.horizontalPadding,
                    scrollTables: _scrollTables,
                  ),
                  if (_generating || revealing) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: padding,
                      child: status != null ? _Status(label: status, style: muted) : const _Spinner(),
                    ),
                  ],
                ],
              );
            }
            if (status != null) {
              return Padding(
                padding: padding,
                child: _Status(label: status, style: muted),
              );
            }
            if (completed && files.isEmpty && changes.isEmpty) {
              return Padding(
                padding: padding,
                child: Text(context.t.base.chat.assistantMessage.noAnswer, style: muted),
              );
            }
            return const SizedBox.shrink();
          },
        ),

        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (files.isNotEmpty || changes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (:toolCall, :path) in changes)
                      _PageButton(
                        icon: toolCall.icon,
                        label: switch (toolCall.moves.length) {
                          final count when count > 1 => context.t.base.chat.moveCount(count: count),
                          _ => fileName(path),
                        },
                        page: ProposedCommitPage(chatId: widget.chatId, toolCall: toolCall, path: path),
                      ),
                    for (final (:toolCall, :path) in files)
                      _PageButton(
                        icon: Icons.description_outlined,
                        label: fileName(path),
                        page: PresentedFilePage(chatId: widget.chatId, toolCall: toolCall, path: path),
                      ),
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

              _Footer(message: message, duration: _duration, style: caption),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens a page about a file of the answer: a change the model proposed, or a file it showed.
class _PageButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget page;

  const _PageButton({required this.icon, required this.label, required this.page});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    return FilledButton.tonalIcon(
      icon: Icon(icon),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: () async {
        await ref.global.dispatchAsync(NavigateAction.push(page));
      },
    );
  }
}

enum _AnswerMenuAction { tableLayout, raw }

/// The actions of a finished answer behind three dots: switching its tables, if it has any, between scrolling sideways
/// when they are wide and fitting the width, and opening what the model got and returned for it (like the web's menu).
class _AnswerMenu extends StatelessWidget {
  final UuidValue chatId;
  final UuidValue messageId;
  final bool hasTable;
  final bool scrollTables;
  final VoidCallback onToggleScrollTables;

  const _AnswerMenu({
    required this.chatId,
    required this.messageId,
    required this.hasTable,
    required this.scrollTables,
    required this.onToggleScrollTables,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ref = context.ref;
    final texts = t.flutter.chat.assistantMessage;
    return PopupMenuButton<_AnswerMenuAction>(
      key: ValueKey('chat.message.$messageId.menu'),
      tooltip: t.base.common.actions,
      icon: const Icon(Icons.more_horiz),
      iconSize: 20,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(minimumSize: const Size(32, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      onSelected: (action) async {
        switch (action) {
          case _AnswerMenuAction.tableLayout:
            onToggleScrollTables();
          case _AnswerMenuAction.raw:
            await ref.global.dispatchAsync(NavigateAction.push(RawAnswerPage(chatId: chatId, messageId: messageId)));
        }
      },
      itemBuilder: (_) => [
        if (hasTable)
          PopupMenuItem(
            key: ValueKey('chat.message.$messageId.tableLayout'),
            value: _AnswerMenuAction.tableLayout,
            child: ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(scrollTables ? texts.fitTables : texts.scrollTables),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          key: ValueKey('chat.message.$messageId.raw'),
          value: _AnswerMenuAction.raw,
          child: ListTile(
            leading: const Icon(Icons.data_object),
            title: Text(t.base.chat.rawAnswerDialog.title),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// One line on the left: the model (cut off when too long, in full on long press), the duration and the cost (or the
/// total tokens if the model has no prices). Tapping the duration shows what took how long, tapping the cost the token
/// usage.
class _Footer extends StatelessWidget {
  final MessageDto message;
  final String? duration;
  final TextStyle? style;

  const _Footer({required this.message, required this.duration, required this.style});

  @override
  Widget build(BuildContext context) {
    final modelName = message.modelName;
    final duration = this.duration;
    final style = this.style?.copyWith(letterSpacing: 0.2);
    final tabular = style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final parts = [
      if (modelName != null)
        Flexible(
          child: Tooltip(
            message: modelName,
            child: _IconText(icon: Icons.smart_toy_outlined, text: modelName, style: style),
          ),
        ),
      if (duration != null)
        GestureDetector(
          key: ValueKey('chat.message.${message.id}.duration'),
          behavior: HitTestBehavior.opaque,
          onTap: () => DurationSheet.show(context, message: message),
          child: Text(duration, style: tabular),
        ),
      if (message.usage case final usage?)
        GestureDetector(
          key: ValueKey('chat.message.${message.id}.usage'),
          behavior: HitTestBehavior.opaque,
          onTap: () => UsageSheet.show(context, usage: usage, cost: message.cost, modelName: modelName),
          child: _UsageLabel(usage: usage, cost: message.cost, style: tabular),
        ),
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    final separator = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('•', style: style),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          for (final (i, part) in parts.indexed) ...[if (i > 0) separator, part],
        ],
      ),
    );
  }
}

/// The cost, or the total tokens if the model has no prices, counting up as the usage of each response comes in while
/// generating.
class _UsageLabel extends StatelessWidget {
  final UsageDto usage;
  final CostDto? cost;
  final TextStyle? style;

  const _UsageLabel({required this.usage, required this.cost, required this.style});

  @override
  Widget build(BuildContext context) {
    // Keyed, so that it jumps rather than counts from tokens to a cost or back.
    return switch (cost) {
      final cost? => AnimatedNumber(
        key: const ValueKey('cost'),
        value: double.tryParse(cost.amount) ?? 0,
        format: (value) => formatCost('$value', cost.currency),
        style: style,
      ),
      null => AnimatedNumber(
        key: const ValueKey('tokens'),
        value: usage.totalTokens.toDouble(),
        format: (value) => formatTokens(value.round()),
        style: style,
      ),
    };
  }
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle? style;

  const _IconText({required this.icon, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
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

/// A spinner with what the answer is doing, e.g. "Thinking…".
class _Status extends StatelessWidget {
  final String label;
  final TextStyle? style;

  const _Status({required this.label, required this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _Spinner(),
        const SizedBox(width: 8),
        Flexible(child: Text(label, style: style)),
      ],
    );
  }
}
