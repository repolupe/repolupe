import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/mirror.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/util/raw_answer.dart';
import 'package:app/widget/chat/code_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

// Mid tones, visible on the light and the dark surface (the web's).
const _systemColor = Color(0xFFFB8C00);
const _userColor = Color(0xFF42A5F5);
const _assistantColor = Color(0xFFAB47BC);

/// What the language model got and returned for an answer, like the web's raw answer dialog: the system prompt and the
/// tools (the same in every answer, so hidden until asked for), then the messages. Everything wraps, so nothing
/// scrolls sideways.
class RawAnswerPage extends StatefulWidget {
  final UuidValue chatId;
  final UuidValue messageId;

  const RawAnswerPage({super.key, required this.chatId, required this.messageId});

  @override
  State<RawAnswerPage> createState() => _RawAnswerPageState();
}

class _RawAnswerPageState extends State<RawAnswerPage> with Refena {
  /// `null` until it is loaded.
  RawAnswerDto? _raw;

  /// The tool of each call in [_raw], by the call's id.
  Map<String, String> _toolNames = const {};

  /// Whether nothing is stored for the answer, as it was interrupted by a restart.
  bool _notAvailable = false;
  String? _error;
  bool _loading = true;
  bool _showSystem = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    ensureRef((_) => _load());
  }

  Future<void> _load() async {
    try {
      final raw = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiGetRawAnswerAction(chatId: widget.chatId, messageId: widget.messageId));
      if (mounted) {
        setState(() {
          _raw = raw;
          _toolNames = raw.toolNames;
        });
      }
    } on ClientError catch (e) {
      if (mounted) {
        setState(() {
          if (e.code == ErrorCode.notFound) {
            _notAvailable = true;
          } else {
            _error = e.userMessage;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _copy(RawAnswerDto raw) async {
    final texts = t.base.chat.rawAnswerDialog;
    try {
      await Clipboard.setData(ClipboardData(text: raw.toJsonText()));
      ref.global.dispatch(ShowSnackBarAction(message: texts.copied));
    } on PlatformException {
      ref.global.dispatch(ShowSnackBarAction(message: texts.copyFailed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = context.t.base.chat.rawAnswerDialog;
    final raw = _raw;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final items = [
      if (_notAvailable) Text(texts.notAvailable, style: muted),
      if (_error case final error?)
        Text(
          texts.loadFailed(error: error),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
      if (raw != null) ...[
        _SystemPrompt(system: raw.system, shown: _showSystem, onToggle: () => setState(() => _showSystem = !_showSystem)),
        if (_showSystem && raw.tools.isNotEmpty) _Tools(tools: raw.tools),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            texts.messages.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 1),
          ),
        ),
        for (final message in raw.messages) _Message(message: message, toolNames: _toolNames),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(texts.title),
        actions: [
          if (raw != null)
            IconButton(
              key: const ValueKey('rawAnswer.copy'),
              icon: const Icon(Icons.copy),
              tooltip: texts.copy,
              onPressed: () => _copy(raw),
            ),
        ],
        bottom: _loading ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, index) => items[index],
          separatorBuilder: (_, _) => const SizedBox(height: 16),
        ),
      ),
    );
  }
}

/// A part of the raw answer, with a line on its start side colored by who it comes from.
class _Group extends StatelessWidget {
  final Color color;
  final List<Widget> children;

  const _Group({required this.color, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: color, width: 3)),
      ),
      padding: const EdgeInsetsDirectional.only(start: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: children),
    );
  }
}

/// A part of a group, e.g. a tool or a tool call, set apart by its [heading] rather than a line.
class _Sub extends StatelessWidget {
  final Widget heading;
  final List<Widget> children;

  const _Sub({required this.heading, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [heading, ...children]);
  }
}

/// The system prompt, shown once asked for.
class _SystemPrompt extends StatelessWidget {
  final String system;
  final bool shown;
  final VoidCallback onToggle;

  const _SystemPrompt({required this.system, required this.shown, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final texts = context.t.base.chat.rawAnswerDialog;
    return _Group(
      color: _systemColor,
      children: [
        Row(
          children: [
            Flexible(child: Text(texts.systemPrompt, style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('rawAnswer.toggleSystem'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onToggle,
              child: Text(shown ? texts.hide : texts.show),
            ),
          ],
        ),
        if (shown) CodeBlock(text: system, wrap: true),
      ],
    );
  }
}

/// The tools the model could call, each with its description and the schema of its arguments.
class _Tools extends StatelessWidget {
  final List<RawToolDto> tools;

  const _Tools({required this.tools});

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleSmall;
    final mono = heading?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']);
    return _Group(
      color: _systemColor,
      children: [
        Text('${context.t.base.chat.rawAnswerDialog.tools} (${tools.length})', style: heading),
        for (final (index, tool) in tools.indexed)
          Padding(
            padding: EdgeInsets.only(top: index > 0 ? 8 : 0),
            child: _Sub(
              heading: Text(tool.name, style: mono),
              children: [
                CodeBlock(text: tool.description, wrap: true),
                CodeBlock(text: formatJsonText(tool.inputSchema), wrap: true),
              ],
            ),
          ),
      ],
    );
  }
}

/// A message as the model got or returned it, block by block.
class _Message extends StatelessWidget {
  final RawMessageDto message;

  /// The tool of each call by the call's id, since a result only has the id.
  final Map<String, String> toolNames;

  const _Message({required this.message, required this.toolNames});

  @override
  Widget build(BuildContext context) {
    final texts = context.t.base.chat.rawAnswerDialog;
    final onlyToolResults = message.onlyToolResults;
    final assistant = message.role == MessageRole.assistant;
    return _Group(
      color: assistant ? _assistantColor : _userColor,
      children: [
        Text(
          assistant
              ? texts.assistant
              : onlyToolResults
              ? texts.toolResult
              : texts.user,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final (index, block) in message.content.indexed)
          if (block is RawBlockDto_Text)
            CodeBlock(text: block.text, wrap: true)
          else if (block is! RawBlockDto_Unknown)
            Padding(
              // More room between two parts with a heading of their own.
              padding: EdgeInsets.only(top: index > 0 && message.content[index - 1] is! RawBlockDto_Text ? 8 : 0),
              child: _Block(block: block, toolNames: toolNames, onlyToolResults: onlyToolResults),
            ),
      ],
    );
  }
}

/// Reasoning, a tool call or its result, under a label telling which.
class _Block extends StatelessWidget {
  final RawBlockDto block;
  final Map<String, String> toolNames;

  /// Whether the message only has tool results, so that its heading already says what they are.
  final bool onlyToolResults;

  const _Block({required this.block, required this.toolNames, required this.onlyToolResults});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = context.t.base.chat.rawAnswerDialog;
    switch (block) {
      case RawBlockDto_Reasoning(:final text):
        return _Sub(
          heading: _Label(icon: Icons.psychology_outlined, text: texts.reasoning),
          children: [
            if (text.isNotEmpty)
              CodeBlock(text: text, wrap: true, italic: true)
            else
              Text(texts.reasoningWithheld, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        );
      case RawBlockDto_ToolUse(:final id, :final name, :final input):
        return _Sub(
          heading: _Label(icon: Icons.build_outlined, text: '${texts.toolUse}: $id'),
          children: [
            CodeBlock(text: name, wrap: true),
            CodeBlock(text: formatJsonText(input), wrap: true),
          ],
        );
      case RawBlockDto_ToolResult(:final toolUseId, :final content, :final isError):
        final call = switch (toolNames[toolUseId]) {
          final name? => '$name ($toolUseId)',
          null => toolUseId,
        };
        return _Sub(
          // Under a "Tool result" heading the call is enough.
          heading: onlyToolResults
              ? _Label(text: call, error: isError)
              : _Label(icon: Icons.keyboard_return, text: '${texts.toolResult}: $call', error: isError),
          children: [CodeBlock(text: content, wrap: true)],
        );
      case RawBlockDto_Text() || RawBlockDto_Unknown():
        return const SizedBox.shrink();
    }
  }
}

/// What a block is, in small muted text that wraps, after an [icon] and before a chip if it is an [error].
class _Label extends StatelessWidget {
  final IconData? icon;
  final String text;
  final bool error;

  const _Label({this.icon, required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return Text.rich(
      TextSpan(
        children: [
          if (icon case final icon?)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Icon(icon, size: 14, color: colors.onSurfaceVariant),
              ),
            ),
          TextSpan(text: text),
          if (error)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsetsDirectional.only(start: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  context.t.base.chat.rawAnswerDialog.error,
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.onErrorContainer),
                ),
              ),
            ),
        ],
      ),
      style: style,
    );
  }
}
