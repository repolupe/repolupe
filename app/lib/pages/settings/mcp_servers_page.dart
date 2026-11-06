import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/widget/page_list_view.dart';
import 'package:app/widget/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// E.g. "3 tools", or "1 of 3 tools enabled", like the web's `mcpToolCountLabel`.
String mcpToolCountLabel(Translations t, McpServerDto server) {
  final count = server.tools.length;
  final enabled = server.tools.where((tool) => !server.disabledTools.contains(tool.name)).length;
  return enabled == count ? t.base.mcpServers.page.toolCount(count: count) : t.base.mcpServers.page.toolCountEnabled(enabled: enabled, count: count);
}

/// The MCP servers the user owns or that are shared with them, each turned on or off for the user's chats, with
/// their tools, which the owner turns on or off for everyone who uses the server. Servers are added, changed and
/// shared in the web app only.
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
  UuidValue? _busy;

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

  /// Runs [change] on [server], then shows [done], or [failed] with the error. The chat page below takes the change.
  Future<void> _change(
    McpServerDto server,
    Future<void> Function() change, {
    required String done,
    required String Function(String error) failed,
  }) async {
    setState(() {
      _busy = server.id;
    });
    try {
      await change();
      ref.global.dispatch(ShowSnackBarAction(message: done));
      unawaited(ref.redux(chatProvider).dispatchAsync(LoadMcpServersAction()));
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: failed(e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
        });
      }
    }
  }

  /// Saves [server] with [enabled] and [disabledTools] (owner only) and shows the result.
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
      setState(() {
        _servers = [for (final s in _servers ?? const <McpServerDto>[]) s.id == updated.id ? updated : s];
      });
    }
  }

  /// Turns the server on or off for the user's chats: the owner's own setting, or the user's for a shared one, which
  /// leaves the owner's alone.
  Future<void> _setEnabled(McpServerDto server, bool enabled) async {
    final texts = t.base.mcpServers.page;
    await _change(
      server,
      () async {
        if (server.shared == null) {
          await _update(server, enabled: enabled, disabledTools: server.disabledTools);
        } else {
          final userId = UuidValue.fromString(ref.read(accountProvider).active!.user.id);
          await ref.redux(apiProvider).dispatchAsync(ApiUpdateMcpServerUserAction(id: server.id, userId: userId, enabled: enabled));
          await _load(quiet: true);
        }
      },
      done: enabled ? texts.enabled(name: server.name) : texts.disabled(name: server.name),
      failed: (error) => texts.toggleFailed(error: error),
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
      failed: (error) => texts.toggleToolFailed(error: error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servers = _servers;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final texts = context.t.base.mcpServers;
    // Users without the permission only turn on the servers shared with them.
    final canManage = context.watch(meProvider.select((user) => user?.canManageMcpServers ?? false));
    return Scaffold(
      appBar: AppBar(title: Text(texts.title)),
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
          ? _EmptyState(canManage: canManage)
          : PageListView(
              key: const ValueKey('mcpServers.list'),
              padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(texts.page.count(count: servers.length), style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(context.t.flutter.mcpServers.page.description, style: muted),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(texts.page.privacy, style: muted),
                ),
                for (final server in servers)
                  _McpServerCard(
                    server: server,
                    // Only the owner changes the server, users it is shared with only use it.
                    canToggle: _busy == null && (server.shared != null || canManage),
                    canToggleTools: _busy == null && server.shared == null && canManage,
                    onEnabledChanged: (enabled) => _setEnabled(server, enabled),
                    onToolChanged: (tool, enabled) => _setToolEnabled(server, tool, enabled),
                  ),
              ],
            ),
    );
  }
}

/// A server: its name, URL (or who shared it) and status, whether the user uses it, and its tools.
class _McpServerCard extends StatelessWidget {
  final McpServerDto server;
  final bool canToggle;
  final bool canToggleTools;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(McpToolDto tool, bool enabled) onToolChanged;

  const _McpServerCard({
    required this.server,
    required this.canToggle,
    required this.canToggleTools,
    required this.onEnabledChanged,
    required this.onToolChanged,
  });

  @override
  Widget build(BuildContext context) {
    final texts = context.t.base.mcpServers.page;
    final theme = Theme.of(context);
    final shared = server.shared;
    final id = server.id;
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
            subtitle: Text(
              shared != null ? texts.sharedBy(name: shared.ownerName) : server.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _McpStatusChip(server: server),
          ),
          SwitchListTile(
            key: ValueKey('mcpServers.$id.enabled'),
            title: Text(texts.useInChats),
            // Before using it, the user should know whose server it is and what it may receive.
            subtitle: shared != null && !shared.enabled ? Text(texts.sharedOff(name: shared.ownerName)) : null,
            value: isMcpServerOn(server),
            onChanged: canToggle ? onEnabledChanged : null,
          ),
          if (server.tools.isNotEmpty)
            ExpansionTile(
              key: ValueKey('mcpServers.$id.tools'),
              title: Text(mcpToolCountLabel(context.t, server)),
              subtitle: shared != null ? Text(texts.sharedWithYouHint) : null,
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                for (final tool in server.tools)
                  SwitchListTile(
                    key: ValueKey('mcpServers.$id.tools.${tool.name}'),
                    dense: true,
                    title: Text(
                      tool.name,
                      style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Courier'], fontWeight: FontWeight.w600),
                    ),
                    subtitle: switch (tool.description ?? (tool.title != tool.name ? tool.title : null)) {
                      final text? => Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
                      null => null,
                    },
                    value: !server.disabledTools.contains(tool.name),
                    onChanged: canToggleTools ? (enabled) => onToolChanged(tool, enabled) : null,
                  ),
              ],
            )
          else if (server.status == McpServerStatus.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(texts.noTools, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// The status of the last connection, with why it failed as tooltip (only for the owner).
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
    final chip = StatusChip(label: label, color: color, icon: icon);
    final lastError = server.lastError;
    return lastError == null
        ? chip
        : Tooltip(
            message: texts.mcpServers.page.lastError(error: lastError),
            child: chip,
          );
  }
}

/// Shown while the user has no servers, which are added in the web app.
class _EmptyState extends StatelessWidget {
  final bool canManage;

  const _EmptyState({required this.canManage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = context.t.base.mcpServers.page;
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
              Text(texts.emptyTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                canManage ? context.t.flutter.mcpServers.page.emptyText : texts.emptyTextShared,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
