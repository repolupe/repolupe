import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/src/rust/api/local.dart';
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
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Dragging closes the sheet even while it can't be popped (the drag handle too), see [PopScope] in build.
      enableDrag: false,
      showDragHandle: false,
      builder: (_) => MistralKeySheet(isSet: isSet),
    );
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
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final canSave = !_loading && _value.trim().isNotEmpty;
    // The back button and taps outside close the sheet only while the instance is not being started.
    return PopScope(
      canPop: !_loading,
      child: Padding(
        // Keeps the field above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      ocrApiKeyMistral,
                      style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']),
                    ),
                    const SizedBox(height: 8),
                    Text(t.flutter.admin.config.mistralKeySheet.intro, style: muted),
                    const SizedBox(height: 20),
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
                        if (canSave) {
                          await _save(_value.trim());
                        }
                      },
                    ),
                    if (_error case final error?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error,
                          key: const ValueKey('config.mistralKey.error'),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    if (widget.isSet)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey('config.mistralKey.remove'),
                            onPressed: _loading ? null : () => _save(null),
                            icon: const Icon(Icons.key_off),
                            label: Text(t.flutter.admin.config.mistralKeySheet.remove),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                // useSafeArea only covers the top.
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.paddingOf(context).bottom),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _loading ? null : () => Navigator.pop(context, false),
                      child: Text(t.base.common.cancel),
                    ),
                    FilledButton(
                      key: const ValueKey('config.mistralKey.save'),
                      onPressed: canSave ? () => _save(_value.trim()) : null,
                      child: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(t.base.common.save),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
