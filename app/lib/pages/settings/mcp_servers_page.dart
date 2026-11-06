import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/mcp_server_form_page.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/mcp_sign_in_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:app/widget/mcp_servers/mcp_server_users_tile.dart';
import 'package:app/widget/page_list_view.dart';
import 'package:app/widget/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('McpServersPage');

bool isMcpToolEnabled(McpServerDto server, McpToolDto tool) => !server.disabledTools.contains(tool.name);

int enabledMcpToolCount(McpServerDto server) => server.tools.where((tool) => isMcpToolEnabled(server, tool)).length;

/// Whether the model gets the server's tools in the user's chats, like the web's `isMcpServerUsed`.
bool isMcpServerUsed(McpServerDto server) => isMcpServerOn(server) && server.status == McpServerStatus.ready && enabledMcpToolCount(server) != 0;

/// E.g. "3 tools", or "1 of 3 tools enabled", like the web's `mcpToolCountLabel`.
String mcpToolCountLabel(Translations t, McpServerDto server) {
  final count = server.tools.length;
  final enabled = enabledMcpToolCount(server);
  return enabled == count ? t.base.mcpServers.page.toolCount(count: count) : t.base.mcpServers.page.toolCountEnabled(enabled: enabled, count: count);
}

/// `disabled_tools` with every tool the server lists turned on, keeping the names it no longer lists.
List<String> _withAllToolsOn(McpServerDto server) => server.disabledTools.where((name) => !server.tools.any((tool) => tool.name == name)).toList();

/// What is being done with a server.
enum _BusyAction { change, refresh, signIn }

/// The MCP servers the user owns or that are shared with them, like the web's page. With the permission to manage MCP
/// servers, the owner adds, renames, refreshes, shares and deletes theirs, and turns their tools on or off for
/// everyone who uses them, and signs in to the ones that ask for it (OAuth, see [McpSignInService]). Each user turns a
/// server on or off for their own chats, and leaves the ones shared with them.
class McpServersPage extends StatefulWidget {
  const McpServersPage({super.key});

  @override
  State<McpServersPage> createState() => _McpServersPageState();
}

class _McpServersPageState extends State<McpServersPage> with Refena {
  /// `null` until they are loaded.
  List<McpServerDto>? _servers;
  bool _loading = false;

  /// The server being changed, one change at a time.
  ({UuidValue id, _BusyAction action})? _busy;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  /// Loads the servers; [quiet] without the progress indicator and without a snack bar if it fails.
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final servers = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListMcpServersAction());
      if (mounted) {
        setState(() {
          _servers = servers;
        });
      }
    } on ClientError catch (e) {
      if (!quiet) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.mcpServers.page.loadFailed(error: e.userMessage)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// The chat page below offers the servers that are on, with their names.
  void _reloadChat() {
    unawaited(ref.redux(chatProvider).dispatchAsync(LoadMcpServersAction()));
  }

  void _replace(McpServerDto server) {
    setState(() {
      _servers = [for (final s in _servers ?? const <McpServerDto>[]) s.id == server.id ? server : s];
    });
  }

  void _remove(McpServerDto server) {
    setState(() {
      _servers = [
        for (final s in _servers ?? const <McpServerDto>[])
          if (s.id != server.id) s,
      ];
    });
  }

  /// Runs [change] on [server], then shows [done], or [failed] with the error.
  Future<void> _change(
    McpServerDto server,
    Future<void> Function() change, {
    required String done,
    required String Function(ClientError error) failed,
  }) async {
    setState(() {
      _busy = (id: server.id, action: _BusyAction.change);
    });
    try {
      await change();
      ref.global.dispatch(ShowSnackBarAction(message: done));
      _reloadChat();
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: failed(e)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
        });
      }
    }
  }

  /// Saves [server] with [enabled] and [disabledTools] (owner only).
  Future<void> _update(McpServerDto server, {required bool enabled, required List<String> disabledTools}) async {
    final updated = await ref
        .redux(apiProvider)
        .dispatchAsyncTakeResult(
          ApiUpdateMcpServerAction(
            id: server.id,
            request: UpdateMcpServerRequest(name: server.name, enabled: enabled, disabledTools: disabledTools),
          ),
        );
    if (mounted) {
      _replace(updated);
    }
  }

  /// Opens the form, then loads the list again with the new server, and offers to sign in to one that asks for it.
  Future<void> _create() async {
    final created = await ref.global.dispatchAsync(NavigateAction.push<McpServerDto>(const McpServerFormPage.create()));
    if (created == null || !mounted) {
      return;
    }
    ref.global.dispatch(ShowSnackBarAction(message: t.base.mcpServers.page.created));
    _reloadChat();
    await _load(quiet: true);
    if (created.status == McpServerStatus.authorizationRequired && mounted) {
      await _offerSignIn(created);
    }
  }

  /// Asks to sign in right away, like the web after adding a server that asks for it.
  Future<void> _offerSignIn(McpServerDto server) async {
    final page = t.base.mcpServers.page;
    final confirmed = await ConfirmDialog.show(
      context,
      title: page.signInTitle(name: server.name),
      text: page.signInText(name: server.name),
      confirmText: page.signIn,
      confirmIcon: Icons.login,
      confirmKey: 'mcpServers.signIn.confirm',
      onConfirm: () async => null,
    );
    if (confirmed && mounted) {
      await _signIn(server);
    }
  }

  /// Signs in to the server in the browser, then connects to it again, like the web's `startSignIn` and its callback
  /// page. Closing the browser cancels it without a message.
  Future<void> _signIn(McpServerDto server) async {
    final page = t.base.mcpServers.page;
    setState(() {
      _busy = (id: server.id, action: _BusyAction.signIn);
    });
    try {
      final Map<String, String>? callback;
      try {
        callback = await ref
            .read(mcpSignInProvider)
            .signIn(
              (redirectUri) => ref.redux(apiProvider).dispatchAsyncTakeResult(ApiAuthorizeMcpServerAction(id: server.id, redirectUri: redirectUri)),
            );
      } on ClientError catch (e) {
        ref.global.dispatch(ShowSnackBarAction(message: page.signInFailed(error: e.userDetail)));
        return;
      } catch (e, st) {
        // No browser, or the authorization URL is not a web page.
        _logger.warning('Could not open the sign-in page', e, st);
        ref.global.dispatch(ShowSnackBarAction(message: t.flutter.mcpServers.page.signInBrowserFailed));
        return;
      }
      if (callback != null) {
        ref.global.dispatch(ShowSnackBarAction(message: await _completeSignIn(callback)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
        });
      }
    }
  }

  /// Completes the sign-in with the [callback] of the authorization server, and returns what to tell the user, like
  /// the web's callback page.
  Future<String> _completeSignIn(Map<String, String> callback) async {
    final texts = t.base.mcpServers.callback;
    String? param(String name) => callback[name]?.isNotEmpty ?? false ? callback[name] : null;

    if (param('error') case final error?) {
      // The text of the authorization server, e.g. when the user denied access.
      final description = param('error_description');
      return error == 'access_denied' && description == null ? texts.denied : texts.serverError(error: description ?? error);
    }
    final state = param('state');
    final code = param('code');
    if (state == null || code == null) {
      return texts.incomplete;
    }
    try {
      final server = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(
            ApiCompleteMcpAuthorizationAction(
              request: McpAuthorizationCallbackRequest(state: state, code: code, iss: param('iss')),
            ),
          );
      if (mounted) {
        _replace(server);
      }
      _reloadChat();
      return server.status == McpServerStatus.ready ? texts.signedIn(name: server.name) : texts.signedInNotReady(name: server.name);
    } on ClientError catch (e) {
      return e.code == ErrorCode.notFound ? texts.expired : texts.failed(error: e.userDetail);
    }
  }

  Future<void> _edit(McpServerDto server) async {
    final updated = await ref.global.dispatchAsync(NavigateAction.push<McpServerDto>(McpServerFormPage.edit(server: server)));
    if (updated == null || !mounted) {
      return;
    }
    _replace(updated);
    ref.global.dispatch(ShowSnackBarAction(message: t.base.mcpServers.page.updated));
    _reloadChat();
  }

  Future<void> _delete(McpServerDto server) async {
    final page = t.base.mcpServers.page;
    final deleted = await ConfirmDialog.show(
      context,
      title: page.deleteTitle,
      text: page.deleteText(name: server.name),
      confirmText: t.base.common.delete,
      confirmIcon: Icons.delete,
      confirmKey: 'mcpServers.delete.confirm',
      onConfirm: () async {
        try {
          await ref.redux(apiProvider).dispatchAsync(ApiDeleteMcpServerAction(id: server.id));
          return null;
        } on ClientError catch (e) {
          return page.deleteFailed(error: e.userMessage);
        }
      },
    );
    if (!deleted || !mounted) {
      return;
    }
    _remove(server);
    ref.global.dispatch(ShowSnackBarAction(message: page.deleted));
    _reloadChat();
  }

  /// Stops using a server shared with the user, who can only use it again once the owner shares it again.
  Future<void> _leave(McpServerDto server, UuidValue userId) async {
    final page = t.base.mcpServers.page;
    final left = await ConfirmDialog.show(
      context,
      title: page.leaveTitle,
      text: page.leaveText(name: server.name),
      confirmText: page.leave,
      confirmIcon: Icons.logout,
      confirmKey: 'mcpServers.leave.confirm',
      onConfirm: () async {
        try {
          await ref.redux(apiProvider).dispatchAsync(ApiRemoveMcpServerUserAction(id: server.id, userId: userId));
          return null;
        } on ClientError catch (e) {
          return page.leaveFailed(error: e.userMessage);
        }
      },
    );
    if (!left || !mounted) {
      return;
    }
    _remove(server);
    ref.global.dispatch(ShowSnackBarAction(message: page.left(name: server.name)));
    _reloadChat();
  }

  /// Connects to the server again and lists its tools. A failed connection is shown in its card.
  Future<void> _refresh(McpServerDto server) async {
    final page = t.base.mcpServers.page;
    setState(() {
      _busy = (id: server.id, action: _BusyAction.refresh);
    });
    try {
      final updated = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiRefreshMcpServerAction(id: server.id));
      if (mounted) {
        _replace(updated);
      }
      ref.global.dispatch(
        ShowSnackBarAction(
          message: switch (updated.status) {
            McpServerStatus.ready => page.refreshed(count: updated.tools.length),
            McpServerStatus.authorizationRequired => page.refreshedSignIn(name: updated.name),
            McpServerStatus.failed || McpServerStatus.unknown => page.refreshedFailed(name: updated.name),
          },
        ),
      );
      _reloadChat();
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: page.refreshFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
        });
      }
    }
  }

  /// Turns the server on or off for the user's chats: the owner's own setting, or the user's for a shared one, which
  /// leaves the owner's alone. The tools stay as they are, since they are the same for everyone.
  Future<void> _setEnabled(McpServerDto server, bool enabled, UuidValue userId) async {
    final texts = t.base.mcpServers.page;
    final shared = server.shared;
    await _change(
      server,
      () async {
        if (shared == null) {
          await _update(server, enabled: enabled, disabledTools: server.disabledTools);
        } else {
          await ref.redux(apiProvider).dispatchAsync(ApiUpdateMcpServerUserAction(id: server.id, userId: userId, enabled: enabled));
          await _load(quiet: true);
        }
      },
      done: enabled ? texts.enabled(name: server.name) : texts.disabled(name: server.name),
      // Tells when the user has as many servers as they may use.
      failed: (e) => texts.toggleFailed(error: shared == null ? e.userMessage : e.userDetail),
    );
  }

  /// Turns a tool on or off for everyone who uses the server. Names the server no longer lists stay in
  /// `disabled_tools`, so those tools stay off if they return.
  Future<void> _setToolEnabled(McpServerDto server, McpToolDto tool, bool enabled) async {
    final texts = t.base.mcpServers.page;
    final disabledTools = enabled ? server.disabledTools.where((name) => name != tool.name).toList() : [...server.disabledTools, tool.name];
    await _change(
      server,
      () => _update(server, enabled: server.enabled, disabledTools: disabledTools),
      done: enabled ? texts.toolEnabled(name: tool.name) : texts.toolDisabled(name: tool.name),
      failed: (e) => texts.toggleToolFailed(error: e.userMessage),
    );
  }

  /// Like [_setToolEnabled], for every tool the server lists.
  Future<void> _setAllToolsEnabled(McpServerDto server, bool enabled) async {
    final texts = t.base.mcpServers.page;
    final disabledTools = enabled ? _withAllToolsOn(server) : {...server.disabledTools, for (final tool in server.tools) tool.name}.toList();
    await _change(
      server,
      () => _update(server, enabled: server.enabled, disabledTools: disabledTools),
      done: enabled ? texts.allToolsEnabled(name: server.name) : texts.allToolsDisabled(name: server.name),
      failed: (e) => texts.toggleAllToolsFailed(error: e.userMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servers = _servers;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final texts = context.t.base.mcpServers;
    final me = context.watch(meProvider);
    // Users without the permission still see their servers, and turn on the ones shared with them.
    final canManage = me?.canManageMcpServers ?? false;
    // The local instance has only one user, who can share with nobody.
    final local = context.watch(accountProvider.select((state) => state.active?.isLocal ?? false));
    final showCreate = canManage && servers != null && servers.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(texts.title)),
      floatingActionButton: showCreate
          ? FloatingActionButton.extended(
              key: const ValueKey('mcpServers.new'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text(texts.newServer),
            )
          : null,
      body: servers == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.t.base.common.retry),
                    ),
                  )
          : servers.isEmpty
          ? _EmptyState(onCreate: canManage ? _create : null)
          : PageListView(
              key: const ValueKey('mcpServers.list'),
              padding: EdgeInsets.only(bottom: (showCreate ? 88 : 24) + MediaQuery.paddingOf(context).bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(texts.page.count(count: servers.length), style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(texts.page.intro, style: muted),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(texts.page.privacy, style: muted),
                ),
                for (final server in servers)
                  _McpServerCard(
                    server: server,
                    // Only the owner changes the server, users it is shared with only use it.
                    manages: server.shared == null && canManage,
                    canToggle: server.shared != null || canManage,
                    local: local,
                    busy: _busy != null,
                    working: _busy?.id == server.id && _busy?.action != _BusyAction.change,
                    onEdit: () => _edit(server),
                    onRefresh: () => _refresh(server),
                    onSignIn: () => _signIn(server),
                    onDelete: () => _delete(server),
                    onLeave: me == null ? null : () => _leave(server, me.id),
                    onEnabledChanged: me == null ? null : (enabled) => _setEnabled(server, enabled, me.id),
                    onToolChanged: (tool, enabled) => _setToolEnabled(server, tool, enabled),
                    onAllToolsChanged: (enabled) => _setAllToolsEnabled(server, enabled),
                  ),
              ],
            ),
    );
  }
}

enum _MenuAction { edit, refresh, signInAgain, delete, leave }

/// A server: its name, URL, status, authentication and whether the user uses it, why it can't be used, its tools and
/// (for the owner) who it is shared with. The owner signs in to it if it asks for it, and edits, refreshes, signs in
/// again (OAuth) and deletes it from the menu, a user it is shared with leaves it there.
class _McpServerCard extends StatelessWidget {
  final McpServerDto server;

  /// Whether the user owns the server and may manage MCP servers: change, refresh, share and delete it, and choose
  /// its tools.
  final bool manages;

  /// Whether the user may turn the server on or off: one shared with them always, their own only if they may manage
  /// MCP servers.
  final bool canToggle;

  /// Whether this is the local instance, whose only user shares with nobody.
  final bool local;

  /// Whether a server is being changed, so none can be changed until it is done.
  final bool busy;

  /// Whether this server is being refreshed or signed in to.
  final bool working;

  final VoidCallback onEdit;
  final VoidCallback onRefresh;
  final VoidCallback onSignIn;
  final VoidCallback onDelete;
  final VoidCallback? onLeave;
  final ValueChanged<bool>? onEnabledChanged;
  final void Function(McpToolDto tool, bool enabled) onToolChanged;
  final ValueChanged<bool> onAllToolsChanged;

  const _McpServerCard({
    required this.server,
    required this.manages,
    required this.canToggle,
    required this.local,
    required this.busy,
    required this.working,
    required this.onEdit,
    required this.onRefresh,
    required this.onSignIn,
    required this.onDelete,
    required this.onLeave,
    required this.onEnabledChanged,
    required this.onToolChanged,
    required this.onAllToolsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final texts = t.base.mcpServers.page;
    final theme = Theme.of(context);
    final shared = server.shared;
    final id = server.id;
    final canToggleTools = !busy && manages;
    final lastError = server.lastError;
    return Card(
      key: ValueKey('mcpServers.$id'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.extension_outlined, color: theme.colorScheme.primary),
            title: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(server.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: working
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : manages || shared != null
                ? PopupMenuButton<_MenuAction>(
                    key: ValueKey('mcpServers.$id.menu'),
                    tooltip: t.base.common.actions,
                    enabled: !busy,
                    onSelected: (action) => switch (action) {
                      _MenuAction.edit => onEdit(),
                      _MenuAction.refresh => onRefresh(),
                      _MenuAction.signInAgain => onSignIn(),
                      _MenuAction.delete => onDelete(),
                      _MenuAction.leave => onLeave?.call(),
                    },
                    itemBuilder: (_) => [
                      if (manages) ...[
                        _menuItem(id, _MenuAction.edit, Icons.edit_outlined, texts.editServer),
                        _menuItem(id, _MenuAction.refresh, Icons.refresh, t.base.common.refresh),
                        // One that asks to sign in has the button below its notice instead.
                        if (server.auth == McpServerAuth.oAuth && server.status != McpServerStatus.authorizationRequired)
                          _menuItem(id, _MenuAction.signInAgain, Icons.login, texts.signInAgain),
                        _menuItem(id, _MenuAction.delete, Icons.delete_outline, texts.deleteServer),
                      ] else
                        _menuItem(id, _MenuAction.leave, Icons.logout, texts.leave),
                    ],
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _McpStatusChip(server: server),
                if (server.status == McpServerStatus.ready && !isMcpServerUsed(server))
                  StatusChip(label: texts.notUsed, color: Colors.grey, icon: Icons.comments_disabled_outlined),
                if (shared != null)
                  Tooltip(
                    message: texts.sharedWithYouHint,
                    child: StatusChip(
                      label: texts.sharedBy(name: shared.ownerName),
                      color: theme.colorScheme.primary,
                      icon: Icons.group,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _ConnectionLine(server: server),
          ),
          if (server.status == McpServerStatus.failed && lastError != null)
            _Notice(
              key: ValueKey('mcpServers.$id.error'),
              kind: _NoticeKind.error,
              text: texts.lastError(error: lastError),
            )
          else if (server.status == McpServerStatus.failed && shared != null)
            _Notice(key: ValueKey('mcpServers.$id.error'), kind: _NoticeKind.error, text: texts.lastErrorShared)
          else if (server.status == McpServerStatus.authorizationRequired) ...[
            _Notice(
              key: ValueKey('mcpServers.$id.signInRequired'),
              kind: shared == null ? _NoticeKind.warning : _NoticeKind.info,
              text: shared == null ? texts.signInRequired : texts.signInRequiredShared,
            ),
            if (manages)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: ValueKey('mcpServers.$id.signIn'),
                    onPressed: busy ? null : onSignIn,
                    icon: const Icon(Icons.login),
                    label: Text(texts.signIn),
                  ),
                ),
              ),
          ],
          SwitchListTile(
            key: ValueKey('mcpServers.$id.enabled'),
            title: Text(texts.useInChats),
            // Before using it, the user should know whose server it is and what it may receive.
            subtitle: shared != null && !shared.enabled ? Text(texts.sharedOff(name: shared.ownerName)) : null,
            value: isMcpServerOn(server),
            onChanged: canToggle && !busy ? onEnabledChanged : null,
          ),
          if (server.tools.isNotEmpty)
            ExpansionTile(
              key: ValueKey('mcpServers.$id.tools'),
              title: Text(mcpToolCountLabel(t, server)),
              subtitle: shared != null ? Text(texts.sharedWithYouHint) : null,
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                SwitchListTile(
                  key: ValueKey('mcpServers.$id.tools.all'),
                  dense: true,
                  title: Text(texts.allTools),
                  // Some tools off counts as off, so turning it on turns all of them on, like the web's indeterminate
                  // checkbox.
                  value: enabledMcpToolCount(server) == server.tools.length,
                  onChanged: canToggleTools ? onAllToolsChanged : null,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                for (final tool in server.tools)
                  SwitchListTile(
                    key: ValueKey('mcpServers.$id.tools.${tool.name}'),
                    dense: true,
                    title: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: tool.name,
                            style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier'], fontWeight: FontWeight.w600),
                          ),
                          if (tool.title case final title? when title != tool.name) TextSpan(text: '  $title'),
                        ],
                      ),
                    ),
                    subtitle: switch (tool.description) {
                      final description? => Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
                      null => null,
                    },
                    value: isMcpToolEnabled(server, tool),
                    onChanged: canToggleTools ? (enabled) => onToolChanged(tool, enabled) : null,
                  ),
              ],
            )
          else if (server.status == McpServerStatus.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(texts.noTools, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          if (manages && !local) McpServerUsersTile(serverId: id),
        ],
      ),
    );
  }

  static PopupMenuItem<_MenuAction> _menuItem(UuidValue id, _MenuAction action, IconData icon, String label) {
    return PopupMenuItem(
      key: ValueKey('mcpServers.$id.${action.name}'),
      value: action,
      child: ListTile(leading: Icon(icon), title: Text(label), contentPadding: EdgeInsets.zero),
    );
  }
}

/// The status of the last connection.
class _McpStatusChip extends StatelessWidget {
  final McpServerDto server;

  const _McpStatusChip({required this.server});

  @override
  Widget build(BuildContext context) {
    final texts = context.t.base;
    final (label, color, icon) = switch (server.status) {
      McpServerStatus.ready => (texts.status.ready, Colors.green, Icons.check_circle),
      McpServerStatus.authorizationRequired => (texts.mcpServers.status.authorizationRequired, Colors.orange, Icons.lock_person),
      McpServerStatus.failed => (texts.status.failed, Colors.red, Icons.error),
      McpServerStatus.unknown => (texts.mcpServers.status.unknown, Colors.grey, Icons.help_outline),
    };
    return StatusChip(label: label, color: color, icon: icon);
  }
}

/// How requests to the server are authenticated, and when it was last connected to (the exact time as tooltip).
class _ConnectionLine extends StatelessWidget {
  final McpServerDto server;

  const _ConnectionLine({required this.server});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = context.t.base.mcpServers.page;
    final color = theme.colorScheme.onSurfaceVariant;
    final tokenHint = server.tokenHint;
    final (label, icon) = switch (server.auth) {
      McpServerAuth.none => (texts.authNone, Icons.lock_open_outlined),
      McpServerAuth.oAuth => (texts.authOAuth, Icons.how_to_reg_outlined),
      McpServerAuth.token || McpServerAuth.unknown => (
        tokenHint == null ? texts.authToken : texts.authTokenHint(hint: tokenHint),
        Icons.key_outlined,
      ),
    };
    return Tooltip(
      message: formatDateTime(server.checkedAt),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label • ${texts.checked(relative: formatRelative(server.checkedAt))}',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

enum _NoticeKind { error, warning, info }

/// Why a server's tools can't be used, like the web's alerts in its card.
class _Notice extends StatelessWidget {
  final _NoticeKind kind;
  final String text;

  const _Notice({super.key, required this.kind, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (color, onColor, icon) = switch (kind) {
      _NoticeKind.error => (colors.errorContainer, colors.onErrorContainer, Icons.error_outline),
      _NoticeKind.warning => (colors.tertiaryContainer, colors.onTertiaryContainer, Icons.warning_amber),
      _NoticeKind.info => (colors.secondaryContainer, colors.onSecondaryContainer, Icons.info_outline),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: onColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: onColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown while the user has no servers, with a button to add one if they may ([onCreate]).
class _EmptyState extends StatelessWidget {
  final VoidCallback? onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = context.t.base.mcpServers;
    final onCreate = this.onCreate;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: pageMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension, size: 64, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(texts.page.emptyTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                onCreate != null ? texts.page.emptyText : texts.page.emptyTextShared,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (onCreate != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('mcpServers.new'),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: Text(texts.newServer),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
