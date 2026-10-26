import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('ChatListService');

final chatListProvider = ReduxProvider<ChatListService, ChatPageDto?>((ref) {
  return ChatListService(api: ref.notifier(apiProvider));
});

/// The newest chats of the active account, shown in the drawer, `null` until they are loaded. Its `nextCursor`
/// continues with the older ones.
class ChatListService extends ReduxNotifier<ChatPageDto?> {
  final ApiService _api;

  ChatListService({required this._api});

  @override
  ChatPageDto? init() => null;
}

/// Loads the newest [limit] chats, keeping the previous ones if it fails.
class LoadChatsAction extends AsyncReduxAction<ChatListService, ChatPageDto?> {
  final int limit;

  LoadChatsAction({required this.limit});

  @override
  Future<ChatPageDto?> reduce() async {
    final client = notifier._api.state;
    if (client == null) {
      return null;
    }

    try {
      final page = await external(notifier._api).dispatchAsyncTakeResult(ApiListChatsAction(limit: limit));
      // Dropped if the account changed in the meantime.
      return notifier._api.state == client ? page : state;
    } on ClientError catch (e) {
      _logger.warning('Cannot load the chats: $e');
      return state;
    }
  }
}

/// Forgets the chats, e.g. when the account changes.
class ClearChatsAction extends ReduxAction<ChatListService, ChatPageDto?> {
  @override
  ChatPageDto? reduce() => null;
}
