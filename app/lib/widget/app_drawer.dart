import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings_page.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/util/format.dart';
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
              child: ListView(
                key: const ValueKey('chat.drawer.chats'),
                padding: EdgeInsets.zero,
                children: [
                  CustomPaint(
                    painter: _TimelinePainter(
                      first: true,
                      last: chats == null || chats.isEmpty,
                      selected: openId == null,
                      colors: Theme.of(context).colorScheme,
                      textDirection: Directionality.of(context),
                    ),
                    child: ListTile(
                      key: const ValueKey('chat.drawer.newChat'),
                      contentPadding: const EdgeInsetsDirectional.only(start: _TimelinePainter.lineStart * 2, end: 16),
                      title: Text(t.base.app.navigation.newChat),
                      selected: openId == null,
                      onTap: () async {
                        // The drawer's context is gone once it is closed.
                        final ref = context.ref;
                        Navigator.pop(context);
                        // Like the app bar's button, keeps the choices of a chat without messages.
                        if (ref.read(chatProvider).messages.isNotEmpty) {
                          await ref.redux(chatProvider).dispatchAsync(NewChatAction());
                        }
                      },
                    ),
                  ),
                  if (chats == null)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (chats.isEmpty)
                    ListTile(title: Text(t.base.chat.noChats))
                  else
                    for (final (index, chat) in chats.indexed)
                      CustomPaint(
                        painter: _TimelinePainter(
                          first: false,
                          last: index == chats.length - 1,
                          selected: chat.id == openId,
                          colors: Theme.of(context).colorScheme,
                          textDirection: Directionality.of(context),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsetsDirectional.only(start: _TimelinePainter.lineStart * 2, end: 16),
                          title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatDayTime(chat.updatedAt)),
                          selected: chat.id == openId,
                          onTap: () async {
                            // The drawer's context is gone once it is closed.
                            final ref = context.ref;
                            Navigator.pop(context);
                            await ref.redux(chatProvider).dispatchAsync(OpenChatAction(chat.id));
                          },
                        ),
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

/// Draws a "git log" next to a chat: a vertical line through the tile with a
/// circle at its center. The line starts at "New chat" and ends at the last chat.
class _TimelinePainter extends CustomPainter {
  /// The distance of the line from the start edge.
  static const lineStart = 24.0;
  static const _radius = 5.0;

  final bool first;
  final bool last;
  final bool selected;
  final ColorScheme colors;
  final TextDirection textDirection;

  const _TimelinePainter({
    required this.first,
    required this.last,
    required this.selected,
    required this.colors,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = textDirection == TextDirection.rtl ? size.width - lineStart : lineStart;
    final center = Offset(x, size.height / 2);
    final line = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 2;
    if (!first) {
      canvas.drawLine(Offset(x, 0), center.translate(0, -_radius), line);
    }
    if (!last) {
      canvas.drawLine(center.translate(0, _radius), Offset(x, size.height), line);
    }
    final circle = Paint()
      ..color = selected ? colors.primary : colors.outline
      ..style = selected ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, selected ? _radius : _radius - 1, circle);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      first != old.first || last != old.last || selected != old.selected || colors != old.colors || textDirection != old.textDirection;
}
