import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/mcp_server_name_picker_page.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/validation.dart';
import 'package:app/widget/page_list_view.dart';
import 'package:app/widget/unsaved_changes_guard.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Adds an MCP server: its name (one of the common servers, which fills in its URL, or one of the user's own), its
/// URL and an optional token, then connects to it. Or renames [server], whose URL and token can't be changed (it is
/// deleted and added again instead). Pops with the added or renamed server.
class McpServerFormPage extends StatefulWidget {
  /// The server being edited, `null` when adding one.
  final McpServerDto? server;

  const McpServerFormPage.create({super.key}) : server = null;

  const McpServerFormPage.edit({super.key, required McpServerDto this.server});

  @override
  State<McpServerFormPage> createState() => _McpServerFormPageState();
}

class _McpServerFormPageState extends State<McpServerFormPage> with Refena {
  bool _saving = false;
  late String _name = widget.server?.name ?? '';
  late String _url = widget.server?.url ?? '';
  String _token = '';
  bool _showToken = false;

  /// Owned here, so picking a name can fill them in.
  late final _nameController = TextEditingController(text: _name);
  late final _urlController = TextEditingController(text: _url);

  bool get _isEdit => widget.server != null;

  /// The fields as they are, compared with [_initialValues] to tell whether there are unsaved changes.
  Object get _values => (_name, _url, _token);

  /// The fields as the page opened.
  late final Object _initialValues;

  bool get _dirty => _values != _initialValues;

  @override
  void initState() {
    super.initState();
    _initialValues = _values;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// Picks the name of a new server; one of the common servers also fills in its URL.
  Future<void> _pickName() async {
    final choice = await ref.global.dispatchAsync(NavigateAction.push<McpServerNameChoice>(McpServerNamePickerPage(name: _name)));
    if (choice == null || !mounted) {
      return;
    }
    setState(() {
      _name = choice.name;
      _nameController.text = _name;
      if (choice.suggestion case final suggestion?) {
        _url = suggestion.url;
        _urlController.text = _url;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.trim();
    final url = _url.trim();
    final error = mcpServerError(name: name, url: url);
    if (error != null) {
      ref.global.dispatch(ShowSnackBarAction(message: error));
      return;
    }

    setState(() {
      _saving = true;
    });
    try {
      final McpServerDto saved;
      final server = widget.server;
      if (server == null) {
        saved = await ref
            .redux(apiProvider)
            .dispatchAsyncTakeResult(
              ApiCreateMcpServerAction(
                request: CreateMcpServerRequest(name: name, url: url, token: trimmedOrNull(_token)),
              ),
            );
      } else {
        saved = await ref
            .redux(apiProvider)
            .dispatchAsyncTakeResult(
              ApiUpdateMcpServerAction(
                id: server.id,
                request: UpdateMcpServerRequest(name: name, enabled: server.enabled, disabledTools: server.disabledTools),
              ),
            );
      }
      if (mounted) {
        Navigator.pop(context, saved);
      }
    } on ClientError catch (e) {
      // The page stays open, so the input can be corrected.
      final texts = t.base.mcpServers;
      ref.global.dispatch(
        ShowSnackBarAction(
          message: _isEdit
              // Renaming a server does not connect to it.
              ? texts.page.saveFailed(error: e.userMessage)
              // Adding one does, and the API's message tells why that failed.
              : texts.page.createFailed(error: e.code == ErrorCode.remoteUnreachable ? texts.unreachable(error: e.userDetail) : e.userDetail),
        ),
      );
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
    final texts = t.base.mcpServers;
    final dialog = texts.dialog;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final isAdmin = context.watch(meProvider.select((user) => user?.role == UserRole.admin));
    return UnsavedChangesGuard(
      dirty: _dirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? dialog.editTitle : texts.newServer),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              TextButton(
                key: const ValueKey('mcpServerForm.save'),
                onPressed: _save,
                child: Text(t.base.common.save),
              ),
          ],
        ),
        body: SafeArea(
          child: PageListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: const ValueKey('mcpServerForm.name'),
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '${t.base.common.name}*',
                  hintText: 'GitHub',
                  prefixIcon: const Icon(Icons.label_outline),
                  suffixIcon: _isEdit ? null : const Icon(Icons.chevron_right),
                ),
                enabled: !_saving,
                // A new server's name is picked on its own page, which offers the common servers, an existing one's is
                // edited here, since its URL can't change anymore.
                readOnly: !_isEdit,
                onTap: _isEdit ? null : _pickName,
                maxLength: maxMcpServerNameLength,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _name = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('mcpServerForm.url'),
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: '${dialog.url}*',
                  // Like the web's persistent placeholder.
                  hintText: 'https://mcp.example.com/mcp',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  helperText: _isEdit
                      ? null
                      : isAdmin
                      ? dialog.urlHintAdmin
                      : dialog.urlHintUser,
                  helperMaxLines: 3,
                  prefixIcon: const Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                enabled: !_saving && !_isEdit,
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _url = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_isEdit)
                Text(dialog.fixedConnection, style: muted)
              else
                StringField(
                  key: const ValueKey('mcpServerForm.token'),
                  value: _token,
                  decoration: InputDecoration(
                    labelText: dialog.tokenOptional,
                    helperText: dialog.tokenHint,
                    helperMaxLines: 3,
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                      tooltip: _showToken ? t.flutter.mcpServers.form.hideToken : t.flutter.mcpServers.form.showToken,
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
                  onSubmitted: (_) async {
                    if (!_saving) {
                      await _save();
                    }
                  },
                ),
              if (_saving && !_isEdit) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(dialog.connecting, style: muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
