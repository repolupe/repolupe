import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/widget/chat/scope_choices.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The MCP servers whose tools a new chat gets, chosen among those that are on (see [ChatState.mcpServers]).
class McpServerSheet extends StatelessWidget {
  const McpServerSheet();

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const McpServerSheet(),
    );
  }

  /// E.g. "All MCP Servers", the name of the only server, or "3 MCP servers".
  static String summary(BuildContext context, ChatState state) {
    if (state.allMcpServers) {
      return context.t.base.chat.allMcpServers;
    }
    final ids = state.mcpServerIds;
    final name = ids.length == 1 ? state.mcpServers.where((s) => s.id == ids.first).firstOrNull?.name : null;
    return name ?? context.t.base.chat.mcpServerCount(count: ids.length);
  }

  /// A puzzle piece, crossed out while no server is chosen.
  static IconData icon(ChatState state) =>
      !state.allMcpServers && state.mcpServerIds.isEmpty ? Icons.extension_off_outlined : Icons.extension_outlined;

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final theme = Theme.of(context);
    final chat = context.redux(chatProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(context.t.base.mcpServers.title, style: theme.textTheme.titleSmall),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: scopeChoices(
                allTitle: context.t.base.chat.allMcpServers,
                all: state.allMcpServers,
                ids: state.mcpServerIds,
                items: [
                  for (final server in state.mcpServers) (id: server.id, title: server.name, subtitle: _problem(context, server)),
                ],
                onChanged: (all, ids) => chat.dispatch(SetMcpServerScopeAction(all: all, ids: ids)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Why the model doesn't get the server's tools for now, `null` if it does: it is not connected, or all of its tools
  /// are turned off. Like the web's `isMcpServerUsed`, for a server that is on.
  static String? _problem(BuildContext context, McpServerDto server) {
    final texts = context.t.base;
    if (server.status != McpServerStatus.ready) {
      return switch (server.status) {
        McpServerStatus.ready => texts.status.ready,
        McpServerStatus.authorizationRequired => texts.mcpServers.status.authorizationRequired,
        McpServerStatus.failed => texts.status.failed,
        McpServerStatus.unknown => texts.mcpServers.status.unknown,
      };
    }
    final count = server.tools.length;
    final enabled = server.tools.where((tool) => !server.disabledTools.contains(tool.name)).length;
    if (enabled != 0) {
      return null;
    }
    return count == 0 ? texts.mcpServers.page.toolCount(count: 0) : texts.mcpServers.page.toolCountEnabled(enabled: 0, count: count);
  }
}
