import 'dart:async';

import 'package:app/service/persistence_service.dart';
import 'package:refena_flutter/refena_flutter.dart';

final chatPanelProvider = ReduxProvider<ChatPanelService, bool>((ref) {
  return ChatPanelService(persistence: ref.read(persistenceProvider));
}, debugLabel: 'ChatPanelVisible');

/// Whether the panel with the chats is shown beside the chat on wide screens: the user hides it and shows it again,
/// like the web's navigation. It stays so when a chat is opened, when the page opens again (e.g. for another account),
/// and when the app restarts, since it is stored on the device.
class ChatPanelService extends ReduxNotifier<bool> {
  final PersistenceService _persistence;

  ChatPanelService({required this._persistence});

  @override
  bool init() => _persistence.getChatPanelVisible();
}

/// Shows the panel or hides it, and stores it. Right away, so that the panel moves when it is tapped, not once it
/// is stored.
class SetChatPanelVisibleAction extends ReduxAction<ChatPanelService, bool> {
  final bool visible;

  SetChatPanelVisibleAction(this.visible);

  @override
  bool reduce() {
    unawaited(notifier._persistence.setChatPanelVisible(visible));
    return visible;
  }
}
