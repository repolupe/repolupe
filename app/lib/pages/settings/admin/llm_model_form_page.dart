import 'package:app/gen/strings.g.dart';
import 'package:app/service/admin_llm_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/util/validation.dart';
import 'package:app/widget/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Adds a model to [provider], or edits [model]: its API name, display name, max output tokens and prices per
/// million tokens (only if the provider has a currency). Pops with the created or updated model.
class LlmModelFormPage extends StatefulWidget {
  final LlmProviderDto provider;

  /// The model being edited, `null` when adding one.
  final LlmModelDto? model;

  /// Whether a new model becomes the default, i.e. there is none yet.
  final bool becomesDefault;

  const LlmModelFormPage.create({super.key, required this.provider, required this.becomesDefault}) : model = null;

  const LlmModelFormPage.edit({super.key, required this.provider, required LlmModelDto this.model}) : becomesDefault = false;

  @override
  State<LlmModelFormPage> createState() => _LlmModelFormPageState();
}

class _LlmModelFormPageState extends State<LlmModelFormPage> with Refena {
  bool _saving = false;
  late String _apiName = widget.model?.apiName ?? '';
  late String _displayName = widget.model?.displayName ?? '';
  late String _maxOutputTokens = widget.model?.maxOutputTokens?.toString() ?? '';
  late String _inputPrice = widget.model?.inputPrice ?? '';
  late String _outputPrice = widget.model?.outputPrice ?? '';
  late String _cacheReadPrice = widget.model?.cacheReadPrice ?? '';
  late String _cacheWritePrice = widget.model?.cacheWritePrice ?? '';

  bool get _isEdit => widget.model != null;
  String? get _currency => widget.provider.currency;

  /// The fields as they are, compared with [_initialValues] to tell whether there are unsaved changes.
  Object get _values => (_apiName, _displayName, _maxOutputTokens, _inputPrice, _outputPrice, _cacheReadPrice, _cacheWritePrice);

  /// The fields as the page opened.
  late final Object _initialValues;

  bool get _dirty => _values != _initialValues;

  @override
  void initState() {
    super.initState();
    _initialValues = _values;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final saved = await ref.global.dispatchAsync(
        SaveLlmModelAction(
          providerId: widget.provider.id,
          modelId: widget.model?.id,
          hasCurrency: _currency != null,
          apiName: _apiName,
          displayName: _displayName,
          maxOutputTokens: _maxOutputTokens,
          inputPrice: _inputPrice,
          outputPrice: _outputPrice,
          cacheReadPrice: _cacheReadPrice,
          cacheWritePrice: _cacheWritePrice,
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

  Widget _priceField({required String keyName, required String label, required String value, String? hint, required ValueChanged<String> onChanged}) {
    return StringField(
      key: ValueKey('modelForm.$keyName'),
      value: value,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: _currency,
        errorText: priceError(value),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      enabled: !_saving,
      textInputAction: TextInputAction.next,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dialog = t.base.admin.llm.modelDialog;
    final form = t.flutter.admin.llm.modelForm;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final currency = _currency;
    return UnsavedChangesGuard(
      dirty: _dirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? dialog.editTitle : dialog.newTitle(provider: widget.provider.name), overflow: TextOverflow.ellipsis),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              TextButton(
                key: const ValueKey('modelForm.save'),
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
                key: const ValueKey('modelForm.apiName'),
                value: _apiName,
                decoration: InputDecoration(
                  labelText: dialog.apiName,
                  hintText: 'claude-opus-5-5',
                  helperText: form.apiNameHint(max: maxModelApiNameLength),
                  prefixIcon: const Icon(Icons.smart_toy_outlined),
                ),
                enabled: !_saving,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _apiName = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              StringField(
                key: const ValueKey('modelForm.displayName'),
                value: _displayName,
                decoration: InputDecoration(
                  labelText: form.displayNameOptional,
                  hintText: _apiName.trim().isEmpty ? 'Claude Opus 5.5' : _apiName.trim(),
                  helperText: form.displayNameHint(max: maxModelDisplayNameLength),
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _displayName = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              StringField(
                key: const ValueKey('modelForm.maxOutputTokens'),
                value: _maxOutputTokens,
                decoration: InputDecoration(
                  labelText: form.maxOutputTokensOptional,
                  helperText: form.maxOutputTokensHint,
                  prefixIcon: const Icon(Icons.numbers),
                  errorText: isValidMaxOutputTokens(_maxOutputTokens) ? null : dialog.tokensInvalid,
                ),
                keyboardType: TextInputType.number,
                enabled: !_saving,
                textInputAction: currency == null ? TextInputAction.done : TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _maxOutputTokens = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.payments_outlined, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(t.base.admin.llm.pricePerMillion, style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                currency == null ? dialog.noCurrency : dialog.priceHint,
                style: muted,
              ),
              if (currency != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _priceField(
                        keyName: 'inputPrice',
                        label: t.base.common.input,
                        value: _inputPrice,
                        onChanged: (value) {
                          setState(() {
                            _inputPrice = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _priceField(
                        keyName: 'outputPrice',
                        label: t.base.common.output,
                        value: _outputPrice,
                        onChanged: (value) {
                          setState(() {
                            _outputPrice = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _priceField(
                        keyName: 'cacheReadPrice',
                        label: dialog.cacheRead,
                        hint: dialog.sameAsInput,
                        value: _cacheReadPrice,
                        onChanged: (value) {
                          setState(() {
                            _cacheReadPrice = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _priceField(
                        keyName: 'cacheWritePrice',
                        label: dialog.cacheWrite,
                        hint: dialog.sameAsInput,
                        value: _cacheWritePrice,
                        onChanged: (value) {
                          setState(() {
                            _cacheWritePrice = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
              if (!_isEdit && widget.becomesDefault) ...[
                const SizedBox(height: 24),
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      dialog.becomesDefault,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
