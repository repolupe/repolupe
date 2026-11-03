import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/widget/chat/mcp_server_sheet.dart';
import 'package:app/widget/chat/repository_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// What the user chose in the [InputOptionsSheet].
enum InputOption { attach, repositories, mcpServers }

/// The options of the message input's plus button: attaching a file, and choosing the repositories the new chat reads
/// and the MCP servers whose tools it gets.
/// Closes with the choice, which the input carries out, so that the next sheet replaces this one.
class InputOptionsSheet extends StatelessWidget {
  const InputOptionsSheet();

  static Future<InputOption?> show(BuildContext context) async {
    return showModalBottomSheet<InputOption>(
      context: context,
      showDragHandle: true,
      builder: (_) => const InputOptionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('chat.options.attach'),
            leading: const Icon(Icons.attach_file),
            title: Text(context.t.base.chat.messageInput.attach),
            onTap: () => Navigator.pop(context, InputOption.attach),
          ),
          if (state.repositories.isNotEmpty)
            ListTile(
              key: const ValueKey('chat.options.repositories'),
              leading: Icon(RepositorySheet.icon(state)),
              title: Text(context.t.base.repositories.title),
              subtitle: Text(RepositorySheet.summary(context, state), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, InputOption.repositories),
            ),
          if (state.mcpServers.isNotEmpty)
            ListTile(
              key: const ValueKey('chat.options.mcpServers'),
              leading: Icon(McpServerSheet.icon(state)),
              title: Text(context.t.base.mcpServers.title),
              subtitle: Text(McpServerSheet.summary(context, state), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, InputOption.mcpServers),
            ),
        ],
      ),
    );
  }
}
