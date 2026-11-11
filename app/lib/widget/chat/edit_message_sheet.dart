import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Edits the text of the [message] the user sent and sends it again, instead of the messages after it.
class EditMessageSheet extends StatefulWidget {
  final MessageDto message;

  const EditMessageSheet({super.key, required this.message});

  static Future<void> show(BuildContext context, {required MessageDto message}) async {
    await FormSheet.show<void>(
      context,
      builder: (_) => EditMessageSheet(message: message),
    );
  }

  @override
  State<EditMessageSheet> createState() => _EditMessageSheetState();
}

class _EditMessageSheetState extends State<EditMessageSheet> with Refena {
  bool _loading = false;
  late String _content = widget.message.content;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref.redux(chatProvider).dispatchAsyncTakeResult(ResendMessageAction(widget.message.id, content: _content));
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
    final removesLater = context.watch(chatProvider.select((state) => state.resendRemovesLater(widget.message.id)));
    return FormSheet(
      title: Text(t.base.chat.editMessageDialog.title),
      description: removesLater ? t.base.chat.editMessageDialog.removesLater : null,
      loading: _loading,
      onSave: _send,
      saveKey: const ValueKey('chat.editMessageDialog.send'),
      saveLabel: t.base.chat.messageInput.send,
      saveIcon: const Icon(Icons.send),
      children: [
        StringField(
          key: const ValueKey('chat.editMessageDialog.content'),
          value: _content,
          label: t.base.chat.placeholder,
          keyboardType: TextInputType.multiline,
          minLines: 3,
          maxLines: 8,
          enabled: !_loading,
          autofocus: true,
          onChanged: (value) {
            setState(() {
              _content = value;
            });
          },
        ),
        if (_error case final error?) InlineError(error, key: const ValueKey('chat.editMessageDialog.error')),
      ],
    );
  }
}
