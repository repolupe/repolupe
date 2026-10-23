import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/code_block.dart';
import 'package:app/widget/chat/tool_call_info.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The input and output of a tool call, like the web's tool call dialog.
class ToolCallPage extends StatefulWidget {
  final UuidValue chatId;
  final ToolCallSummaryDto toolCall;

  const ToolCallPage({super.key, required this.chatId, required this.toolCall});

  @override
  State<ToolCallPage> createState() => _ToolCallPageState();
}

class _ToolCallPageState extends State<ToolCallPage> with Refena {
  /// `null` until it is loaded.
  ToolCallDto? _toolCall;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    ensureRef((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final toolCall = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(ApiGetToolCallAction(chatId: widget.chatId, toolCallId: widget.toolCall.id));
      if (mounted) {
        setState(() => _toolCall = toolCall);
      }
    } on ClientError catch (e) {
      if (mounted) {
        setState(() => _error = e.userMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _toolCall?.summary ?? widget.toolCall;
    final output = _toolCall?.output;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final heading = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(summary.name),
        actions: [
          if (summary.status == ToolCallStatus.running)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.t.base.common.refresh,
              onPressed: _loading ? null : _load,
            ),
        ],
        bottom: _loading ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(child: ToolCallLocation(toolCall: summary, path: null)),
                ToolCallStatusIcon(status: summary.status),
              ],
            ),
            if (summary.commitSha case final sha?) ...[
              const SizedBox(height: 4),
              Text(context.t.flutter.chat.toolCallPage.commit(sha: sha.substring(0, sha.length.clamp(0, 8))), style: muted),
            ],
            const SizedBox(height: 16),
            Text(context.t.base.common.input.toUpperCase(), style: heading),
            const SizedBox(height: 8),
            CodeBlock(text: _prettyJson(summary.input)),
            const SizedBox(height: 16),
            Text(context.t.base.common.output.toUpperCase(), style: heading),
            const SizedBox(height: 8),
            if (_error case final error?)
              Text(error, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error))
            else if (output != null)
              CodeBlock(text: output)
            else if (summary.status == ToolCallStatus.running)
              Text(context.t.base.chat.toolCallDialog.stillRunning, style: muted)
            else if (!_loading)
              Text(context.t.base.chat.toolCallDialog.noOutput, style: muted),
          ],
        ),
      ),
    );
  }
}

/// [json] indented, as it is if it is not JSON.
String _prettyJson(String json) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
  } on FormatException {
    return json;
  }
}
