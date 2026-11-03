import 'package:app/config/theme.dart';
import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_list_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/widget/app_drawer.dart';
import 'package:app/widget/chat/instance_hero.dart';
import 'package:app/widget/chat/leave_temporary_dialog.dart';
import 'package:app/widget/chat/message_input.dart';
import 'package:app/widget/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The width of the messages, and of the message input below them.
const _maxWidth = 800.0;

/// A chat with the model of the active account, a new one every time the page opens.
/// The drawer lists the previous chats to open instead, and the accounts.
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
    final state = context.watch(chatProvider);
    final chat = state.chat;
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
          drawer: const AppDrawer(),
          onDrawerChanged: (opened) async {
            if (opened) {
              await ref.redux(chatListProvider).dispatchAsync(LoadChatsAction(limit: 10));
            }
          },
          appBar: AppBar(
            backgroundColor: WidgetStateColor.resolveWith(
              (states) => states.contains(WidgetState.scrolledUnder) ? scrolledUnder : background,
            ),
            leading: Builder(
              // Below the Scaffold, to find it.
              builder: (context) => IconButton(
                key: const ValueKey('chat.drawer'),
                icon: const Icon(Icons.menu),
                tooltip: context.t.base.chat.title,
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            // A new chat chooses its repositories in the message input.
            title: chat == null ? null : Text(chat.title, overflow: TextOverflow.ellipsis),
            actions: [
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
                ),
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
            ],
          ),
          body: body,
          bottomNavigationBar: const _MessageInputBar(),
        );
      },
      child: SafeArea(
        // The bottom padding is the message input's height, which only the messages scroll behind.
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: state.loading
                ? const SafeArea(child: Center(child: CircularProgressIndicator()))
                : chat == null || state.messages.isEmpty
                ? SafeArea(child: InstanceHero(temporary: state.isTemporary))
                : MessageList(chatId: chat.id, messages: state.messages, modelName: state.modelName),
          ),
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
