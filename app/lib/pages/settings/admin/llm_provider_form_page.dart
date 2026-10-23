import 'package:app/gen/strings.g.dart';
import 'package:app/service/admin_llm_service.dart';
import 'package:app/src/rust/api/mirror.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/util/validation.dart';
import 'package:app/widget/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

const _defaultCurrency = 'USD';

/// Mirrors `LlmApiFormat::default_base_url` in the API: used when the base URL is left empty.
String defaultBaseUrl(LlmApiFormat format) => switch (format) {
  LlmApiFormat.anthropic => 'https://api.anthropic.com',
  LlmApiFormat.openAi => 'https://api.openai.com/v1',
};

/// E.g. `OpenAI` or `Anthropic`, the API format as the pages show it.
String apiFormatLabel(LlmApiFormat format) => switch (format) {
  LlmApiFormat.anthropic => 'Anthropic',
  LlmApiFormat.openAi => 'OpenAI',
};

/// What happens to the API key of a provider being edited (the key itself is never returned).
enum _KeyAction { keep, remove, set }

/// Creates an LLM provider, or edits [provider]: its name, API format, base URL (empty for the official API), API
/// key and the currency of its model prices. Pops with the created or updated provider.
class LlmProviderFormPage extends StatefulWidget {
  /// The provider being edited, `null` when creating one.
  final LlmProviderDto? provider;

  const LlmProviderFormPage.create({super.key}) : provider = null;

  const LlmProviderFormPage.edit({super.key, required LlmProviderDto this.provider});

  @override
  State<LlmProviderFormPage> createState() => _LlmProviderFormPageState();
}

class _LlmProviderFormPageState extends State<LlmProviderFormPage> with Refena {
  bool _saving = false;
  late String _name = widget.provider?.name ?? '';
  late LlmApiFormat _apiFormat = widget.provider?.apiFormat ?? LlmApiFormat.openAi;

  /// The official API is shown as the hint, so switching the format follows it.
  late String _baseUrl = switch (widget.provider) {
    final provider? when provider.baseUrl != defaultBaseUrl(provider.apiFormat) => provider.baseUrl,
    _ => '',
  };
  String _apiKey = '';
  bool _showKey = false;
  late _KeyAction _keyAction = _hadKey ? _KeyAction.keep : _KeyAction.remove;
  late String _currency = widget.provider == null ? _defaultCurrency : (widget.provider!.currency ?? '');

  bool get _isEdit => widget.provider != null;
  bool get _hadKey => widget.provider?.apiKey != null;
  String? get _keyHint => widget.provider?.apiKey?.hint;

  /// The fields as they are, compared with [_initialValues] to tell whether there are unsaved changes.
  Object get _values => (_name, _apiFormat, _baseUrl, _apiKey, _keyAction, _currency);

  /// The fields as the page opened.
  late final Object _initialValues;

  bool get _dirty => _values != _initialValues;

  @override
  void initState() {
    super.initState();
    _initialValues = _values;
  }

  /// Whether the base URL now points to another host, so the current key cannot be kept (the server rejects
  /// `KEEP` then, so the key is never sent to a server it was not entered for).
  bool get _hostChanged {
    final provider = widget.provider;
    if (provider == null) {
      return false;
    }
    final next = originOf(trimmedOrNull(_baseUrl) ?? defaultBaseUrl(_apiFormat));
    return next != null && next != originOf(provider.baseUrl);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final provider = widget.provider;
      final saved = provider == null
          ? await ref.global.dispatchAsync(
              CreateLlmProviderAction(name: _name, apiFormat: _apiFormat, baseUrl: _baseUrl, apiKey: _apiKey, currency: _currency),
            )
          : await ref.global.dispatchAsync(
              UpdateLlmProviderAction(
                id: provider.id,
                name: _name,
                apiFormat: _apiFormat,
                baseUrl: _baseUrl,
                apiKey: switch (_keyAction) {
                  _KeyAction.keep => const ApiKeyChange.keep(),
                  _KeyAction.remove => const ApiKeyChange.remove(),
                  _KeyAction.set => ApiKeyChange.set_(value: _apiKey),
                },
                currency: _currency,
              ),
            );
      // The page stays open if it failed, so the input can be corrected.
      if (saved != null && mounted) {
        Navigator.pop(context, saved);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dialog = t.base.admin.llm.providerDialog;
    final form = t.flutter.admin.llm.providerForm;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return UnsavedChangesGuard(
      dirty: _dirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? dialog.editTitle : t.base.admin.llm.newProvider),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              TextButton(
                key: const ValueKey('providerForm.save'),
                onPressed: _save,
                child: Text(t.base.common.save),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StringField(
                key: const ValueKey('providerForm.name'),
                value: _name,
                decoration: InputDecoration(
                  labelText: t.base.common.name,
                  hintText: 'Anthropic',
                  helperText: dialog.nameLength(max: maxLlmProviderNameLength),
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                enabled: !_saving,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _name = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Text(dialog.apiFormat, style: theme.textTheme.titleSmall),
              RadioGroup<LlmApiFormat>(
                groupValue: _apiFormat,
                onChanged: _saving
                    ? (_) {}
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _apiFormat = value;
                          });
                        }
                      },
                child: Column(
                  children: [
                    RadioListTile(
                      key: const ValueKey('providerForm.format.openai'),
                      value: LlmApiFormat.openAi,
                      title: Text(form.openAiTitle),
                      subtitle: Text(form.openAiDescription),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile(
                      key: const ValueKey('providerForm.format.anthropic'),
                      value: LlmApiFormat.anthropic,
                      title: const Text('Anthropic'),
                      subtitle: Text(form.anthropicDescription),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              StringField(
                key: const ValueKey('providerForm.baseUrl'),
                value: _baseUrl,
                decoration: InputDecoration(
                  labelText: dialog.baseUrl,
                  hintText: defaultBaseUrl(_apiFormat),
                  helperText: form.baseUrlHint,
                  prefixIcon: const Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _baseUrl = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              StringField(
                key: const ValueKey('providerForm.currency'),
                value: _currency,
                decoration: InputDecoration(
                  labelText: dialog.currency,
                  hintText: _defaultCurrency,
                  helperText: form.currencyHint,
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                enabled: !_saving,
                textInputAction: _isEdit ? TextInputAction.done : TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _currency = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_isEdit) ...[
                Text(dialog.apiKey, style: theme.textTheme.titleSmall),
                Text(
                  dialog.currentKey(
                    key: _keyHint != null
                        ? '•••• $_keyHint'
                        : _hadKey
                        ? dialog.keySet
                        : dialog.keyNone,
                  ),
                  style: muted,
                ),
                RadioGroup<_KeyAction>(
                  groupValue: _keyAction,
                  onChanged: _saving
                      ? (_) {}
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _keyAction = value;
                            });
                          }
                        },
                  child: Column(
                    children: [
                      if (_hadKey)
                        RadioListTile(
                          key: const ValueKey('providerForm.key.keep'),
                          value: _KeyAction.keep,
                          title: Text(dialog.keepKey),
                          contentPadding: EdgeInsets.zero,
                        ),
                      RadioListTile(
                        key: const ValueKey('providerForm.key.remove'),
                        value: _KeyAction.remove,
                        title: Text(_hadKey ? dialog.removeKey : dialog.noKey),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile(
                        key: const ValueKey('providerForm.key.set'),
                        value: _KeyAction.set,
                        title: Text(dialog.setKey),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                if (_hadKey && _keyAction == _KeyAction.keep && _hostChanged)
                  Card(
                    key: const ValueKey('providerForm.hostChanged'),
                    color: theme.colorScheme.tertiaryContainer,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        dialog.hostChanged,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                      ),
                    ),
                  ),
              ],
              if (!_isEdit || _keyAction == _KeyAction.set)
                StringField(
                  key: const ValueKey('providerForm.apiKey'),
                  value: _apiKey,
                  decoration: InputDecoration(
                    labelText: _isEdit ? dialog.newKey : form.apiKeyOptional,
                    helperText: _isEdit ? null : form.apiKeyHint,
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                      tooltip: _showKey ? form.hideKey : form.showKey,
                      onPressed: () {
                        setState(() {
                          _showKey = !_showKey;
                        });
                      },
                    ),
                  ),
                  obscureText: !_showKey,
                  keyboardType: TextInputType.visiblePassword,
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) {
                    setState(() {
                      _apiKey = value;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
