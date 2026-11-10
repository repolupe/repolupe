import 'dart:ui' show lerpDouble;

import 'package:app/config/theme.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/llm_page.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_panel_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/instance_name_provider.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/app_drawer.dart';
import 'package:app/widget/chat/greeting_hero.dart';
import 'package:app/widget/chat/leave_temporary_dialog.dart';
import 'package:app/widget/chat/message_input.dart';
import 'package:app/widget/chat/message_list.dart';
import 'package:app/widget/chat/rename_chat_sheet.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The width of the messages, and of the message input below them.
const _maxWidth = 800.0;

/// From this window width on, the chats are a panel beside the chat instead of in the drawer: Material's expanded
/// window class, which iPads have in portrait too. The chat beside it is still as wide as on a large phone.
const _panelMinWidth = 840.0;

/// Below this window height (Material's compact height class), i.e. on a phone in landscape, the chats stay in the
/// drawer even if it is wide enough.
const _panelMinHeight = 480.0;

/// A chat with the model of the active account, a new one every time the page opens.
/// The drawer, on wide screens a panel beside the chat, lists the previous chats to open instead, and the settings.
class ChatPage extends StatefulWidget {
  /// The repositories the new chat reads instead of all of them, e.g. opened from a repository's page.
  final List<UuidValue>? repositoryIds;

  const ChatPage({super.key, this.repositoryIds});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with Refena {
  @override
  void initState() {
    super.initState();
    // The page opens again when the account changes.
    ensureRef((ref) {
      ref.redux(chatListProvider).dispatch(ClearChatsAction());
      // ignore: discarded_futures
      ref.redux(chatProvider).dispatchAsync(NewChatAction(repositoryIds: widget.repositoryIds));
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= _panelMinWidth && size.height >= _panelMinHeight;
    final panelVisible = context.watch(chatPanelProvider);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: panelVisible ? 1 : 0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: _Chat(wide: wide, panel: wide && panelVisible),
      builder: (context, shown, chat) => Stack(
        fit: StackFit.expand,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) _Panel(visible: panelVisible, shown: shown),
              // The chat stays in its place with or without the panel (e.g. when resized in split view), keeping its
              // state. The messages and the message input center in its width.
              Expanded(child: chat!),
            ],
          ),
          if (wide) _PanelButton(visible: panelVisible, shown: shown),
        ],
      ),
    );
  }
}

/// The chat itself, with the drawer on narrow screens. On [wide] ones, its app bar leaves the leading space free for
/// the [_PanelButton] while the [panel] is hidden.
class _Chat extends StatelessWidget {
  final bool wide;

  /// Whether the panel is shown beside the chat.
  final bool panel;

  const _Chat({required this.wide, required this.panel});

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final chat = state.chat;
    // Without a model, questions can't be answered, so admins are offered to add a provider (users only learn it when
    // they send one).
    final noModel = state.loaded && state.models.isEmpty && context.watch(meProvider.select((user) => user?.role == UserRole.admin));
    // Fades to the temporary background, the app bar too because it has the page's color.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: state.isTemporary ? 1 : 0),
      duration: const Duration(milliseconds: 250),
      builder: (context, temporary, body) {
        final colors = Theme.of(context).colorScheme;
        final background = Color.lerp(colors.surface, colors.temporary, temporary)!;
        final scrolledUnder = Color.lerp(colors.surfaceContainer, colors.temporaryContainer, temporary)!;
        return Scaffold(
          backgroundColor: background,
          // The messages scroll on behind the message input, which the body's bottom padding includes.
          // The input stays above the keyboard on its own, so the body extends behind it too.
          extendBody: true,
          resizeToAvoidBottomInset: false,
          drawer: wide ? null : const AppDrawer(),
          appBar: AppBar(
            backgroundColor: WidgetStateColor.resolveWith(
              (states) => states.contains(WidgetState.scrolledUnder) ? scrolledUnder : background,
            ),
            leading: wide
                ? (panel ? null : const SizedBox())
                : Builder(
                    // Below the Scaffold, to find it.
                    builder: (context) => IconButton(
                      key: const ValueKey('chat.drawer'),
                      icon: const Icon(Icons.menu),
                      tooltip: context.t.base.chat.title,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
            // A new chat, which chooses its repositories in the message input, shows the server's name instead.
            title: chat == null ? const _InstanceName() : Text(chat.title, overflow: TextOverflow.ellipsis),
            // "New chat" stays second from the end: the last button is the toggle of a new chat, else the menu.
            actions: [
              IconButton(
                key: const ValueKey('chat.newChat'),
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: context.t.base.app.navigation.newChat,
                onPressed: state.messages.isEmpty
                    ? null
                    : () async {
                        if (await LeaveTemporaryDialog.confirm(context) && context.mounted) {
                          await context.redux(chatProvider).dispatchAsync(NewChatAction());
                        }
                      },
              ),
              if (chat == null)
                IconButton(
                  key: const ValueKey('chat.temporary'),
                  icon: Icon(state.temporary ? Icons.close : Icons.history_toggle_off),
                  tooltip: state.temporary ? context.t.flutter.chat.page.temporaryOff : context.t.base.chat.temporary,
                  onPressed: state.busy
                      ? null
                      : () {
                          context.redux(chatProvider).dispatch(SetTemporaryAction(!state.temporary));
                        },
                )
              // A temporary chat is neither renamed nor deleted, it is deleted on its own.
              else if (!chat.temporary)
                _ChatMenu(chat: chat, enabled: !state.busy),
            ],
          ),
          body: body,
          bottomNavigationBar: const _MessageInputBar(),
        );
      },
      child: SafeArea(
        // The bottom padding is the message input's height, which only the messages scroll behind.
        bottom: false,
        child: !state.loading && chat != null && state.messages.isNotEmpty
            ? MessageList(chatId: chat.id, messages: state.messages, maxWidth: _maxWidth)
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: SafeArea(
                    child: state.loading
                        ? const Center(child: CircularProgressIndicator())
                        : GreetingHero(
                            temporary: state.isTemporary,
                            action: noModel ? const _AddProviderButton() : null,
                          ),
                  ),
                ),
              ),
      ),
    );
  }
}

enum _ChatMenuAction { rename, delete }

/// The actions of the open [chat], like the web's menu beside its title: renaming and deleting it.
class _ChatMenu extends StatelessWidget {
  final ChatDto chat;
  final bool enabled;

  const _ChatMenu({required this.chat, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PopupMenuButton<_ChatMenuAction>(
      key: const ValueKey('chat.menu'),
      tooltip: t.base.chat.page.actions,
      enabled: enabled,
      onSelected: (action) async {
        switch (action) {
          case _ChatMenuAction.rename:
            await RenameChatSheet.show(context, title: chat.title);
          case _ChatMenuAction.delete:
            final chats = context.redux(chatProvider);
            await ConfirmDialog.show(
              context,
              title: t.base.chat.page.deleteTitle,
              text: t.base.chat.page.deleteConfirm(title: chat.title),
              confirmText: t.base.common.delete,
              confirmIcon: Icons.delete,
              confirmKey: 'chat.delete.confirm',
              onConfirm: () => chats.dispatchAsyncTakeResult(DeleteChatAction()),
            );
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const ValueKey('chat.menu.rename'),
          value: _ChatMenuAction.rename,
          child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(t.base.chat.page.rename), contentPadding: EdgeInsets.zero),
        ),
        PopupMenuItem(
          key: const ValueKey('chat.menu.delete'),
          value: _ChatMenuAction.delete,
          child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(t.base.common.delete), contentPadding: EdgeInsets.zero),
        ),
      ],
    );
  }
}

/// Opens the LLM settings, where the admin adds a provider and its models. The chat loads the models again then.
class _AddProviderButton extends StatelessWidget {
  const _AddProviderButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const ValueKey('chat.addProvider'),
      icon: const Icon(Icons.add),
      label: Text(context.t.base.chat.startPage.addProviderLink),
      onPressed: () async {
        await context.ref.global.dispatchAsync(NavigateAction.push(const LlmPage()));
      },
    );
  }
}

/// The server's name (`INSTANCE_NAME`) as the title of a new chat, fading in once loaded.
class _InstanceName extends StatelessWidget {
  const _InstanceName();

  @override
  Widget build(BuildContext context) {
    final instanceName = context.watch(instanceNameProvider).data;
    return AnimatedOpacity(
      opacity: instanceName == null ? 0 : 1,
      duration: const Duration(milliseconds: 250),
      child: Text(instanceName ?? productName, overflow: TextOverflow.ellipsis),
    );
  }
}

/// The [AppDrawer] as a panel beside the chat on wide screens, with the divider. Hidden, it slides out to the start,
/// but stays built, so that it keeps its chats (and their scroll position) for when it is shown again.
class _Panel extends StatelessWidget {
  /// Whether it is shown, or being shown. While hidden, its tiles can't be reached with the keyboard or a screen
  /// reader either.
  final bool visible;

  /// How far it is shown, from 0 to 1.
  final double shown;

  const _Panel({required this.visible, required this.shown});

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: ClipRect(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            widthFactor: shown,
            // Constant, so that the frames of the animation don't rebuild it.
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Not tinted for a temporary chat, which it doesn't list: only the chat beside it is temporary.
                AppDrawer(permanent: true),
                VerticalDivider(width: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The button that hides the [_Panel] and shows it again, above the page, like the web's navigation: at the end of the
/// panel's header while it is shown, else in the chat's app bar, where phones have the button that opens the drawer.
/// It moves between them with the panel, while its arrow (pointing where the panel goes) turns into the menu icon.
class _PanelButton extends StatelessWidget {
  /// Whether the panel is shown, or being shown.
  final bool visible;

  /// How far the panel is shown, from 0 to 1.
  final double shown;

  const _PanelButton({required this.visible, required this.shown});

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    // The app bar's leading space starts after the safe area, the space in the panel's header ends with the panel.
    final inset = Directionality.of(context) == TextDirection.ltr ? padding.left : padding.right;
    final navigation = context.t.base.app.navigation;
    return PositionedDirectional(
      top: padding.top,
      start: lerpDouble(inset, AppDrawer.panelWidth - kToolbarHeight, shown),
      // The app bar's leading space, and the one at the end of the panel's header.
      width: kToolbarHeight,
      height: AppBarTheme.of(context).toolbarHeight ?? kToolbarHeight,
      child: Center(
        child: IconButton(
          key: const ValueKey('chat.panel'),
          // In the color of the app bar's leading button.
          style: IconButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
          icon: AnimatedIcon(icon: AnimatedIcons.menu_arrow, progress: AlwaysStoppedAnimation(shown)),
          tooltip: visible ? navigation.collapseNavigation : navigation.expandNavigation,
          onPressed: () => context.ref.redux(chatPanelProvider).dispatch(SetChatPanelVisibleAction(!visible)),
        ),
      ),
    );
  }
}

/// The [MessageInput] at the bottom of the page, above the keyboard (the page doesn't resize for it), else above the
/// system's bottom area, as wide as the messages.
class _MessageInputBar extends StatelessWidget {
  const _MessageInputBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      // The keyboard consumes the bottom padding.
      maintainBottomViewPadding: true,
      minimum: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: const MessageInput(),
        ),
      ),
    );
  }
}
