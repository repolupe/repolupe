import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings_page.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The newest chats of the account; tapping one opens it with its messages.
/// At the bottom, the settings.
class AppDrawer extends StatelessWidget {
  const AppDrawer();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final chats = context.watch(chatListProvider);
    final openId = context.watch(chatProvider.select((state) => state.chat?.id));
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(t.base.chat.title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Expanded(
              child: chats == null
                  ? const Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : chats.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: ListTile(title: Text(t.base.chat.noChats)),
                    )
                  : ListView(
                      key: const ValueKey('chat.drawer.chats'),
                      padding: EdgeInsets.zero,
                      children: [
                        for (final chat in chats)
                          ListTile(
                            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            selected: chat.id == openId,
                            onTap: () async {
                              // The drawer's context is gone once it is closed.
                              final ref = context.ref;
                              Navigator.pop(context);
                              await ref.redux(chatProvider).dispatchAsync(OpenChatAction(chat.id));
                            },
                          ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('chat.settings'),
              leading: const Icon(Icons.settings),
              title: Text(t.base.settings.title),
              onTap: () async {
                // The drawer's context is gone once it is closed.
                final ref = context.ref;
                Navigator.pop(context);
                await ref.global.dispatchAsync(NavigateAction.push(const SettingsPage()));
              },
            ),
          ],
        ),
      ),
    );
  }
}
