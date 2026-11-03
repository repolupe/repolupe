import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Warns before another chat (or a new one) replaces the temporary chat under way, see [ChatState.startedTemporary].
class LeaveTemporaryDialog extends StatelessWidget {
  const LeaveTemporaryDialog();

  /// Returns whether the open chat may be left: right away if no temporary chat is under way, else if the user
  /// confirms.
  static Future<bool> confirm(BuildContext context) async {
    if (!context.read(chatProvider).startedTemporary) {
      return true;
    }
    final leave = await showDialog<bool>(context: context, builder: (_) => const LeaveTemporaryDialog());
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      title: Text(t.flutter.chat.leaveTemporaryDialog.title),
      content: Text(t.flutter.chat.leaveTemporaryDialog.text),
      actions: [
        TextButton(
          key: const ValueKey('chat.leaveTemporary.cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.base.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('chat.leaveTemporary.leave'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.flutter.chat.leaveTemporaryDialog.leave),
        ),
      ],
    );
  }
}
