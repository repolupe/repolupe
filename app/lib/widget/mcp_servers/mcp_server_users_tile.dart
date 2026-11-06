import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:app/widget/share_user_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The users an MCP server is shared with, for its owner, in the server's card: share it with another user, or stop
/// sharing it. Like the web's `McpServerSharingPanel`, loaded when first expanded.
class McpServerUsersTile extends StatefulWidget {
  final UuidValue serverId;

  const McpServerUsersTile({super.key, required this.serverId});

  @override
  State<McpServerUsersTile> createState() => _McpServerUsersTileState();
}

class _McpServerUsersTileState extends State<McpServerUsersTile> with Refena {
  /// `null` until loaded.
  List<McpServerUserDto>? _users;
  bool _loading = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final users = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListMcpServerUsersAction(id: widget.serverId));
      if (mounted) {
        setState(() {
          _users = users;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.mcpServers.sharing.loadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _share() async {
    final texts = t.base.mcpServers;
    final shared = await ShareUserSheet.show(
      context,
      title: texts.shareDialog.title,
      description: texts.shareDialog.description,
      shareLabel: texts.sharing.share,
      keyPrefix: 'mcpServers.share',
      onShare: (userNameOrEmail) async {
        try {
          await ref
              .redux(apiProvider)
              .dispatchAsync(
                ApiAddMcpServerUserAction(
                  id: widget.serverId,
                  request: AddMcpServerUserRequest(userNameOrEmail: userNameOrEmail),
                ),
              );
          return null;
        } on ClientError catch (e) {
          return e.code == ErrorCode.unknownUser ? texts.sharing.unknownUser : e.userMessage;
        }
      },
    );
    if (!shared || !mounted) {
      return;
    }
    ref.global.dispatch(ShowSnackBarAction(message: texts.sharing.shared));
    await _load();
  }

  Future<void> _remove(McpServerUserDto user) async {
    final sharing = t.base.mcpServers.sharing;
    final removed = await ConfirmDialog.show(
      context,
      title: sharing.stopSharingTitle,
      text: sharing.stopSharingText(name: user.userName),
      confirmText: sharing.stopSharing,
      confirmIcon: Icons.person_remove,
      confirmKey: 'mcpServers.users.remove.confirm',
      onConfirm: () async {
        try {
          await ref.redux(apiProvider).dispatchAsync(ApiRemoveMcpServerUserAction(id: widget.serverId, userId: user.userId));
          return null;
        } on ClientError catch (e) {
          return sharing.stopFailed(error: e.userMessage);
        }
      },
    );
    if (!removed || !mounted) {
      return;
    }
    ref.global.dispatch(ShowSnackBarAction(message: sharing.stopped));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final sharing = context.t.base.mcpServers.sharing;
    final users = _users;
    final id = widget.serverId;
    return ExpansionTile(
      key: ValueKey('mcpServers.$id.sharing'),
      title: Text(sharing.title),
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      onExpansionChanged: (expanded) async {
        if (expanded && users == null && !_loading) {
          await _load();
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(sharing.description, style: muted),
        ),
        if (users == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      key: ValueKey('mcpServers.$id.users.retry'),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.t.base.common.retry),
                    ),
                  ),
          )
        else if (users.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(sharing.notShared, style: muted),
          )
        else
          for (final (i, user) in users.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              key: ValueKey('mcpServers.$id.users.${user.userId}'),
              leading: const Icon(Icons.person),
              title: Text(user.userName),
              subtitle: Tooltip(
                message: formatDateTime(user.createdAt),
                child: Text([?user.email, sharing.sharedAt(relative: formatRelative(user.createdAt))].join('\n')),
              ),
              isThreeLine: user.email != null,
              trailing: IconButton(
                key: ValueKey('mcpServers.$id.users.remove.${user.userId}'),
                tooltip: sharing.stopSharing,
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: () => _remove(user),
              ),
            ),
          ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: ValueKey('mcpServers.$id.share'),
              onPressed: users == null ? null : _share,
              icon: const Icon(Icons.share),
              label: Text(sharing.share),
            ),
          ),
        ),
      ],
    );
  }
}
