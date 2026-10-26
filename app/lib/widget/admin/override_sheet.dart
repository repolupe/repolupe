import 'package:app/gen/strings.g.dart';
import 'package:app/service/admin_config_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
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
/// override is in effect instead until it is removed. The sheet stays open if the API rejects the value.
class OverrideSheet extends StatefulWidget {
  final ConfigEntryDto entry;

  /// All settings, since the API replaces all overrides at once.
  final List<ConfigEntryDto> entries;

  const OverrideSheet({super.key, required this.entry, required this.entries});

  /// Returns the settings as the API lists them after saving, `null` if the sheet was dismissed.
  static Future<List<ConfigEntryDto>?> show(BuildContext context, {required ConfigEntryDto entry, required List<ConfigEntryDto> entries}) async {
    return FormSheet.show<List<ConfigEntryDto>>(
      context,
      builder: (_) => OverrideSheet(entry: entry, entries: entries),
    );
  }

  @override
  State<OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends State<OverrideSheet> with Refena {
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
    final choices = _choices;
    return FormSheet(
      title: Text(
        widget.entry.key,
        style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier']),
      ),
      loading: _loading,
      onSave: () => _save(_value),
      saveKey: const ValueKey('config.override.save'),
      extraAction: widget.entry.overrideValue != null
          ? TextButton.icon(
              key: const ValueKey('config.override.remove'),
              onPressed: _loading ? null : () => _save(null),
              icon: const Icon(Icons.settings_backup_restore),
              label: Text(t.flutter.admin.config.overrideDialog.remove),
            )
          : null,
      children: [
        if (choices != null)
          DropdownButtonFormField<String>(
            key: const ValueKey('config.override.choice'),
            initialValue: choices.contains(_value) ? _value : _useEnv,
            decoration: InputDecoration(labelText: t.base.admin.config.overrideDialog.value),
            items: [
              DropdownMenuItem(value: _useEnv, child: Text('(${widget.entry.env ?? t.base.admin.config.page.notSet})')),
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
            // An empty field uses the env value, so it is shown where the override goes.
            hint: widget.entry.env,
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
        if (_error case final error?) InlineError(error, key: const ValueKey('config.override.error')),
      ],
    );
  }
}
