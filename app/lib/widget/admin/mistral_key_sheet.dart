import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/src/rust/api/local.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The setting [MistralKeySheet] sets.
const ocrApiKeyMistral = 'OCR_API_KEY_MISTRAL';

/// Sets or removes the API key of Mistral's OCR (`OCR_API_KEY_MISTRAL`) of the local instance, which has no
/// environment to set it in. The key is kept in the app's secure storage, and the instance is started again with it.
/// The sheet stays open if the instance can't be started with it, and can't be closed while it starts, so the page
/// loads the settings of the new instance and the error is shown.
class MistralKeySheet extends StatefulWidget {
  /// Whether a key is set, which can then be removed.
  final bool isSet;

  const MistralKeySheet({super.key, required this.isSet});

  /// Returns whether the key was changed.
  static Future<bool> show(BuildContext context, {required bool isSet}) async {
    final changed = await FormSheet.show<bool>(context, enableDrag: false, builder: (_) => MistralKeySheet(isSet: isSet));
    return changed ?? false;
  }

  @override
  State<MistralKeySheet> createState() => _MistralKeySheetState();
}

class _MistralKeySheetState extends State<MistralKeySheet> with Refena {
  bool _loading = false;
  String _value = '';

  /// Why the instance could not be started with the key, until the next try.
  String? _error;

  /// Saves [key], `null` removes it.
  Future<void> _save(String? key) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.redux(accountProvider).dispatchAsync(SetLocalOcrApiKeyMistralAction(key));
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on LocalError catch (e) {
      if (mounted) {
        setState(() {
          _error = t.flutter.account.localStartFailed(message: e.message);
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
    final canSave = _value.trim().isNotEmpty;
    return FormSheet(
      title: const Text(
        ocrApiKeyMistral,
        style: TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier']),
      ),
      description: t.flutter.admin.config.mistralKeySheet.intro,
      loading: _loading,
      onSave: canSave ? () => _save(_value.trim()) : null,
      saveKey: const ValueKey('config.mistralKey.save'),
      extraAction: widget.isSet
          ? TextButton.icon(
              key: const ValueKey('config.mistralKey.remove'),
              onPressed: _loading ? null : () => _save(null),
              icon: const Icon(Icons.key_off),
              label: Text(t.flutter.admin.config.mistralKeySheet.remove),
            )
          : null,
      children: [
        StringField(
          key: const ValueKey('config.mistralKey.value'),
          value: _value,
          label: t.base.admin.llm.providerDialog.apiKey,
          enabled: !_loading,
          autofocus: true,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) {
            setState(() {
              _value = value;
            });
          },
          onSubmitted: (_) async {
            if (!_loading && canSave) {
              await _save(_value.trim());
            }
          },
        ),
        if (_error case final error?) InlineError(error, key: const ValueKey('config.mistralKey.error')),
      ],
    );
  }
}
