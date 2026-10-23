import 'package:app/gen/strings.g.dart';
import 'package:app/service/admin_config_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Keys that accept only a few values, offered as a dropdown; see `RuntimeConfig::set` in the API.
const _options = <String, List<String>>{
  'OCR_ENGINE': ['none', 'tesseract', 'paddle', 'mistral'],
};

/// The dropdown's choice of no override.
const _useEnv = '';

/// Overrides a runtime setting of the server, or removes its override: the environment value stays as it is, the
/// override is in effect instead until it is removed. The dialog stays open if the API rejects the value.
class OverrideDialog extends StatefulWidget {
  final ConfigEntryDto entry;

  /// All settings, since the API replaces all overrides at once.
  final List<ConfigEntryDto> entries;

  const OverrideDialog({super.key, required this.entry, required this.entries});

  /// Returns the settings as the API lists them after saving, `null` if the dialog was dismissed.
  static Future<List<ConfigEntryDto>?> show(BuildContext context, {required ConfigEntryDto entry, required List<ConfigEntryDto> entries}) async {
    return showDialog<List<ConfigEntryDto>>(
      context: context,
      builder: (_) => OverrideDialog(entry: entry, entries: entries),
    );
  }

  @override
  State<OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<OverrideDialog> with Refena {
  bool _loading = false;
  late String _value = widget.entry.overrideValue ?? '';

  /// Why the API rejected the last value, until the next try.
  String? _error;

  List<String>? get _choices => _options[widget.entry.key];

  /// Saves [value] as the override, `null` (or blank) removes it.
  Future<void> _save(String? value) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.global.dispatchAsync(SetConfigOverrideAction(entries: widget.entries, key: widget.entry.key, value: value));
      if (!mounted) {
        return;
      }
      if (result.entries case final entries?) {
        Navigator.pop(context, entries);
      } else {
        setState(() {
          _error = result.error;
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
    final env = widget.entry.env;
    final choices = _choices;
    return AlertDialog(
      title: Text(t.base.admin.config.overrideAction),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.entry.key,
            style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']),
          ),
          const SizedBox(height: 4),
          Text(t.base.admin.config.overrideDialog.env(value: env ?? t.base.admin.config.page.notSet), style: muted),
          const SizedBox(height: 20),
          if (choices != null)
            DropdownButtonFormField<String>(
              key: const ValueKey('config.override.choice'),
              initialValue: choices.contains(_value) ? _value : _useEnv,
              decoration: InputDecoration(
                labelText: t.base.admin.config.overrideDialog.value,
                helperText: t.flutter.admin.config.overrideDialog.choiceHint,
              ),
              items: [
                DropdownMenuItem(value: _useEnv, child: Text(t.base.admin.config.page.useEnv)),
                for (final choice in choices) DropdownMenuItem(value: choice, child: Text(choice)),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _value = value ?? _useEnv;
                      });
                    },
            )
          else
            StringField(
              key: const ValueKey('config.override.value'),
              value: _value,
              label: t.base.admin.config.overrideDialog.value,
              hint: t.base.admin.config.overrideDialog.emptyHint,
              enabled: !_loading,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (value) {
                setState(() {
                  _value = value;
                });
              },
              onSubmitted: (_) async {
                if (!_loading) {
                  await _save(_value);
                }
              },
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                key: const ValueKey('config.override.error'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          if (widget.entry.overrideValue != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('config.override.remove'),
                  onPressed: _loading ? null : () => _save(null),
                  icon: const Icon(Icons.settings_backup_restore),
                  label: Text(t.flutter.admin.config.overrideDialog.remove),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(t.base.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('config.override.save'),
          onPressed: _loading ? null : () => _save(_value),
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
