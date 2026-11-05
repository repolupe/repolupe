import 'package:app/gen/strings.g.dart';
import 'package:app/pages/older_chats_page.dart';
import 'package:app/pages/settings_page.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/chat/leave_temporary_dialog.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// How many of the newest chats are listed, the others are behind "Older".
const _chatCount = 10;

/// The width of the [AppDrawer.permanent] panel, the same as the drawer's.
const _panelWidth = 304.0;

/// The newest chats of the account; tapping one opens it with its messages. Below them "Older", if there are
/// more, opens the others. At the bottom, the settings.
///
/// The chats are loaded whenever it is built: when the drawer opens (its content is built only while it is open), or
/// when the panel is shown.
class AppDrawer extends StatefulWidget {
  /// Whether it is the panel beside the chat on wide screens instead of the modal drawer. It stays open then, also
  /// while the chat goes on beside it, until it is hidden with [onHide].
  final bool permanent;

  /// Hides the [permanent] panel, with a button at the end of its header (where the web has its collapse button).
  final VoidCallback? onHide;

  const AppDrawer({this.permanent = false, this.onHide});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> with Refena {
  /// The chat that is being opened, selected while it loads. The chat page has no chat then, which would select
  /// "New chat" in the panel in between.
  UuidValue? _opening;

  @override
  void initState() {
    super.initState();
    // After the ClearChatsAction of the page, whose post-frame callback is registered first, so that the panel of a
    // new account doesn't keep showing the chats of the previous one.
    ensureRef((ref) => _load());
  }

  Future<void> _load() => ref.redux(chatListProvider).dispatchAsync(LoadChatsAction(limit: _chatCount));

  /// Closes the drawer before an action. The panel stays open, and popping would close the page instead.
  void _close() {
    if (!widget.permanent) {
      Navigator.pop(context);
    }
  }

  /// The drawer around [child], or the panel: in the drawer's color, but flat and square as part of the page, which
  /// draws the divider beside it.
  Widget _frame({required Widget child}) {
    if (!widget.permanent) {
      return Drawer(child: child);
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(width: _panelWidth, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final page = context.watch(chatListProvider);
    final chats = page?.items;
    final olderCursor = page?.nextCursor;
    final (openId, _) = context.watch(
      chatProvider.select((state) => (state.chat?.id, state.sending)),
      // Sending a message creates its chat or moves it to the top, which the panel shows while the chat goes on beside
      // it.
      listener: (prev, next) {
        if (prev.sending && !next.sending) {
          // ignore: discarded_futures
          _load();
        }
      },
    );
    final selectedId = _opening ?? openId;
    final title = Text(t.base.chat.title, style: Theme.of(context).textTheme.titleSmall);
    return _frame(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.onHide case final onHide?)
              // As high as the chat's app bar beside it, so that the button lines up with the app bar's buttons.
              SizedBox(
                height: AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(padding: const EdgeInsetsDirectional.only(start: 16), child: title),
                    ),
                    IconButton(
                      key: const ValueKey('chat.drawer.hide'),
                      icon: const Icon(Icons.menu_open),
                      tooltip: t.base.app.navigation.collapseNavigation,
                      onPressed: onHide,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              )
            else
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: title),
            Expanded(
              child: ListView(
                key: const ValueKey('chat.drawer.chats'),
                padding: EdgeInsets.zero,
                children: [
                  CustomPaint(
                    painter: _TimelinePainter(
                      first: true,
                      last: chats == null || chats.isEmpty,
                      selected: selectedId == null,
                      colors: Theme.of(context).colorScheme,
                      textDirection: Directionality.of(context),
                    ),
                    child: ListTile(
                      key: const ValueKey('chat.drawer.newChat'),
                      contentPadding: const EdgeInsetsDirectional.only(start: _TimelinePainter.lineStart * 2, end: 16),
                      title: Text(t.base.app.navigation.newChat),
                      selected: selectedId == null,
                      onTap: () async {
                        // Like the app bar's button, keeps the choices of a chat without messages.
                        final leave = context.read(chatProvider).messages.isNotEmpty;
                        // Asked above the drawer, which stays open if the user stays.
                        if ((leave && !await LeaveTemporaryDialog.confirm(context)) || !context.mounted) {
                          return;
                        }
                        // The drawer's context is gone once it is closed.
                        final ref = context.ref;
                        _close();
                        setState(() => _opening = null);
                        if (leave) {
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
                  else ...[
                    for (final chat in chats)
                      CustomPaint(
                        painter: _TimelinePainter(
                          first: false,
                          last: olderCursor == null && chat == chats.last,
                          selected: chat.id == selectedId,
                          colors: Theme.of(context).colorScheme,
                          textDirection: Directionality.of(context),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsetsDirectional.only(start: _TimelinePainter.lineStart * 2, end: 16),
                          title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatDayTime(chat.updatedAt)),
                          selected: chat.id == selectedId,
                          onTap: () async {
                            // Asked above the drawer, which stays open if the user stays.
                            if (!await LeaveTemporaryDialog.confirm(context) || !context.mounted) {
                              return;
                            }
                            // The drawer's context is gone once it is closed.
                            final ref = context.ref;
                            _close();
                            setState(() => _opening = chat.id);
                            try {
                              await ref.redux(chatProvider).dispatchAsync(OpenChatAction(chat.id));
                            } finally {
                              if (mounted && _opening == chat.id) {
                                setState(() => _opening = null);
                              }
                            }
                          },
                        ),
                      ),
                    // Only when there are chats it does not show.
                    if (olderCursor != null)
                      CustomPaint(
                        painter: _TimelinePainter(
                          first: false,
                          last: true,
                          selected: false,
                          colors: Theme.of(context).colorScheme,
                          textDirection: Directionality.of(context),
                        ),
                        child: ListTile(
                          key: const ValueKey('chat.drawer.older'),
                          contentPadding: const EdgeInsetsDirectional.only(start: _TimelinePainter.lineStart * 2, end: 16),
                          title: Text(t.base.app.navigation.older),
                          onTap: () async {
                            // The drawer's context is gone once it is closed.
                            final ref = context.ref;
                            _close();
                            await ref.global.dispatchAsync(NavigateAction.push(OlderChatsPage(cursor: olderCursor)));
                          },
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
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
                _close();
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
/// circle at its center. The line starts at "New chat" and ends at "Older", or the last chat without it.
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
