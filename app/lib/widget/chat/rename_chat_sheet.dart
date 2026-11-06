import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Renames the open chat, starting with its current [title].
class RenameChatSheet extends StatefulWidget {
  final String title;

  const RenameChatSheet({super.key, required this.title});

  static Future<void> show(BuildContext context, {required String title}) async {
    await FormSheet.show<void>(
      context,
      builder: (_) => RenameChatSheet(title: title),
    );
  }

  @override
  State<RenameChatSheet> createState() => _RenameChatSheetState();
}

class _RenameChatSheetState extends State<RenameChatSheet> with Refena {
  bool _loading = false;
  late String _title = widget.title;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref.redux(chatProvider).dispatchAsyncTakeResult(RenameChatAction(_title));
      if (!mounted) {
        return;
      }
      if (error == null) {
        Navigator.pop(context);
      } else {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FormSheet(
      title: Text(t.base.chat.renameDialog.title),
      loading: _loading,
      onSave: _save,
      saveKey: const ValueKey('chat.renameDialog.save'),
      children: [
        StringField(
          key: const ValueKey('chat.renameDialog.title'),
          value: _title,
          label: t.base.chat.renameDialog.label,
          enabled: !_loading,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) {
            setState(() {
              _title = value;
            });
          },
          onSubmitted: (_) async {
            if (!_loading) {
              await _save();
            }
          },
        ),
        if (_error case final error?) InlineError(error, key: const ValueKey('chat.renameDialog.error')),
      ],
    );
  }
}
