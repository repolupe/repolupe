import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/mirror.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/format.dart';
import 'package:app/util/validation.dart';
import 'package:app/widget/repositories/repository_kind_sheet.dart';
import 'package:app/widget/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

const _defaultBranch = 'main';
const _defaultPollIntervalSeconds = 900;

/// What happens to the access token of a repository being edited (the token itself is never returned).
enum _TokenAction { keep, remove, set }

/// Creates a repository of a [kind], or edits [repository] (a local one stays local, one with a remote keeps it).
/// Pops with the created or updated repository.
class RepositoryFormPage extends StatefulWidget {
  final RepositoryKind kind;

  /// The repository being edited, `null` when creating one.
  final RepositoryDto? repository;

  const RepositoryFormPage.create({super.key, required this.kind}) : repository = null;

  RepositoryFormPage.edit({super.key, required RepositoryDto this.repository})
    : kind = repository.remote == null ? RepositoryKind.local : RepositoryKind.remote;

  @override
  State<RepositoryFormPage> createState() => _RepositoryFormPageState();
}

class _RepositoryFormPageState extends State<RepositoryFormPage> with Refena {
  bool _saving = false;
  late String _name = widget.repository?.name ?? '';
  late String _description = widget.repository?.description ?? '';
  late String _url = widget.repository?.remote?.url ?? '';
  late String _branch = widget.repository?.remote?.branch ?? _defaultBranch;
  late int _pollIntervalSeconds = widget.repository?.remote?.pollIntervalSeconds ?? _defaultPollIntervalSeconds;
  String _token = '';
  bool _showToken = false;
  late bool _allowCommits = widget.repository?.allowCommits ?? true;
  late _TokenAction _tokenAction = _hadToken ? _TokenAction.keep : _TokenAction.remove;

  bool get _isRemote => widget.kind == RepositoryKind.remote;
  bool get _isEdit => widget.repository != null;
  bool get _hadToken => widget.repository?.remote?.token != null;
  String? get _tokenHint => widget.repository?.remote?.token?.hint;

  /// The fields as they are, compared with [_initialValues] to tell whether there are unsaved changes.
  Object get _values => (_name, _description, _url, _branch, _pollIntervalSeconds, _token, _tokenAction, _allowCommits);

  /// The fields as the page opened.
  late final Object _initialValues;

  bool get _dirty => _values != _initialValues;

  @override
  void initState() {
    super.initState();
    _initialValues = _values;
  }

  /// Used as the name when the name field is left empty, e.g. `owner/repo` of the URL.
  String get _suggestedName => _isRemote && !_isEdit ? (repositoryNameOf(_url) ?? _url.trim()) : '';

  /// Whether the remote moved to another host, so its token cannot be kept (the server rejects `KEEP` then).
  bool get _hostChanged {
    final next = originOf(_url);
    return next != null && next != originOf(widget.repository?.remote?.url ?? '');
  }

  /// The choices of the interval, plus the current one if it was set through the API to another value.
  List<(int, String)> get _pollIntervalOptions {
    final current = widget.repository?.remote?.pollIntervalSeconds;
    if (current == null || pollIntervalOptions.any((o) => o.$1 == current)) {
      return pollIntervalOptions;
    }
    return [...pollIntervalOptions, (current, formatPollInterval(current))]..sort((a, b) => a.$1.compareTo(b.$1));
  }

  Future<void> _save() async {
    final name = _name.trim().isEmpty ? _suggestedName : _name.trim();
    final description = trimmedOrNull(_description);
    final error = repositoryError(name: name, description: description);
    if (error != null) {
      ref.global.dispatch(ShowSnackBarAction(message: error));
      return;
    }
    final url = _url.trim();
    final branch = _branch.trim();
    final token = _token.trim();
    if (_isRemote) {
      if (url.isEmpty) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.missingRemoteUrl));
        return;
      }
      if (branch.isEmpty) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.missingBranch));
        return;
      }
      if (_isEdit && _tokenAction == _TokenAction.set && token.isEmpty) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.editDialog.missingToken));
        return;
      }
    }

    setState(() {
      _saving = true;
    });
    try {
      final RepositoryDto saved;
      final repository = widget.repository;
      if (repository == null) {
        saved = await ref
            .redux(apiProvider)
            .dispatchAsyncTakeResult(
              ApiCreateRepositoryAction(
                request: CreateRepositoryRequest(
                  name: name,
                  description: description,
                  remote: _isRemote
                      ? RemoteSettings(url: url, branch: branch, pollIntervalSeconds: _pollIntervalSeconds, token: trimmedOrNull(token))
                      : null,
                  allowCommits: _allowCommits,
                ),
              ),
            );
      } else {
        saved = await ref
            .redux(apiProvider)
            .dispatchAsyncTakeResult(
              ApiUpdateRepositoryAction(
                id: repository.id,
                request: UpdateRepositoryRequest(
                  name: name,
                  description: description,
                  remote: _isRemote
                      ? RemoteSettingsChange(
                          url: url,
                          branch: branch,
                          pollIntervalSeconds: _pollIntervalSeconds,
                          token: switch (_tokenAction) {
                            _TokenAction.keep => const TokenChange.keep(),
                            _TokenAction.remove => const TokenChange.remove(),
                            _TokenAction.set => TokenChange.set_(value: token),
                          },
                        )
                      : null,
                  allowCommits: _allowCommits,
                ),
              ),
            );
      }
      if (mounted) {
        Navigator.pop(context, saved);
      }
    } on ClientError catch (e) {
      // The page stays open, so the input can be corrected.
      ref.global.dispatch(ShowSnackBarAction(message: e.userMessage));
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
    final theme = Theme.of(context);
    final isAdmin = context.watch(meProvider.select((user) => user?.role == UserRole.admin));
    final repositories = context.t.base.repositories;
    final title = _isEdit
        ? repositories.editDialog.title
        : _isRemote
        ? repositories.createDialog.titleRemote
        : repositories.createDialog.titleLocal;
    return UnsavedChangesGuard(
      dirty: _dirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              TextButton(
                key: const ValueKey('repositoryForm.save'),
                onPressed: _save,
                child: Text(context.t.base.common.save),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_isRemote) ...[
                StringField(
                  key: const ValueKey('repositoryForm.url'),
                  value: _url,
                  decoration: InputDecoration(
                    labelText: repositories.remoteUrl,
                    hintText: 'https://github.com/owner/repo.git',
                    helperText: isAdmin ? repositories.createDialog.remoteUrlHintAdmin : repositories.createDialog.remoteUrlHintUser,
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  enabled: !_saving,
                  autofocus: !_isEdit,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) {
                    setState(() {
                      _url = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              StringField(
                key: const ValueKey('repositoryForm.name'),
                value: _name,
                decoration: InputDecoration(
                  labelText: context.t.base.common.name,
                  hintText: _suggestedName.isEmpty ? null : _suggestedName,
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                enabled: !_saving,
                autofocus: !_isRemote && !_isEdit,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _name = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              StringField(
                key: const ValueKey('repositoryForm.description'),
                value: _description,
                decoration: InputDecoration(
                  labelText: repositories.createDialog.descriptionOptional,
                  helperText: repositories.createDialog.descriptionHint,
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.notes),
                ),
                keyboardType: TextInputType.multiline,
                minLines: 2,
                maxLines: 5,
                enabled: !_saving,
                onChanged: (value) {
                  setState(() {
                    _description = value;
                  });
                },
              ),
              if (_isRemote) ...[
                const SizedBox(height: 16),
                StringField(
                  key: const ValueKey('repositoryForm.branch'),
                  value: _branch,
                  decoration: InputDecoration(labelText: repositories.branch, prefixIcon: const Icon(Icons.account_tree_outlined)),
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  onChanged: (value) {
                    setState(() {
                      _branch = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const ValueKey('repositoryForm.pollInterval'),
                  initialValue: _pollIntervalSeconds,
                  decoration: InputDecoration(labelText: repositories.syncInterval, prefixIcon: const Icon(Icons.timer_outlined)),
                  items: [for (final (seconds, label) in _pollIntervalOptions) DropdownMenuItem(value: seconds, child: Text(label))],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _pollIntervalSeconds = value;
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                if (_isEdit) ...[
                  Text(repositories.accessToken, style: theme.textTheme.titleSmall),
                  RadioGroup<_TokenAction>(
                    groupValue: _tokenAction,
                    onChanged: _saving
                        ? (_) {}
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _tokenAction = value;
                              });
                            }
                          },
                    child: Column(
                      children: [
                        if (_hadToken)
                          RadioListTile(
                            key: const ValueKey('repositoryForm.token.keep'),
                            value: _TokenAction.keep,
                            title: Text(
                              _tokenHint == null ? repositories.editDialog.keepToken : repositories.editDialog.keepTokenWithHint(hint: _tokenHint!),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        RadioListTile(
                          key: const ValueKey('repositoryForm.token.remove'),
                          value: _TokenAction.remove,
                          title: Text(_hadToken ? repositories.editDialog.removeToken : repositories.editDialog.noToken),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile(
                          key: const ValueKey('repositoryForm.token.set'),
                          value: _TokenAction.set,
                          title: Text(repositories.editDialog.setToken),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  if (_hadToken && _tokenAction == _TokenAction.keep && _hostChanged)
                    Card(
                      color: theme.colorScheme.tertiaryContainer,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          repositories.editDialog.hostChanged,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                        ),
                      ),
                    ),
                ],
                if (!_isEdit || _tokenAction == _TokenAction.set) ...[
                  StringField(
                    key: const ValueKey('repositoryForm.token'),
                    value: _token,
                    decoration: InputDecoration(
                      labelText: _isEdit ? repositories.editDialog.newToken : repositories.createDialog.tokenOptional,
                      helperText: _isEdit ? repositories.editDialog.newTokenHint : repositories.createDialog.tokenHint,
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                        tooltip: _showToken ? context.t.flutter.repositories.form.hideToken : context.t.flutter.repositories.form.showToken,
                        onPressed: () {
                          setState(() {
                            _showToken = !_showToken;
                          });
                        },
                      ),
                    ),
                    obscureText: !_showToken,
                    keyboardType: TextInputType.visiblePassword,
                    enabled: !_saving,
                    textInputAction: TextInputAction.done,
                    onChanged: (value) {
                      setState(() {
                        _token = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('repositoryForm.allowCommits'),
                title: Text(repositories.allowCommits),
                subtitle: _isRemote ? null : Text(repositories.createDialog.allowCommitsHintLocal),
                secondary: const Icon(Icons.edit_outlined),
                contentPadding: EdgeInsets.zero,
                value: _allowCommits,
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _allowCommits = value;
                        });
                      },
              ),
              if (_saving && _isRemote) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  repositories.createDialog.checkingRemote,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
