import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// How many chats are loaded at once, like the web's list.
const _pageSize = 50;

/// The chats older than those in the drawer, newest first; more are loaded when scrolled to the end.
/// Tapping one opens it.
class OlderChatsPage extends StatefulWidget {
  /// The drawer's `nextCursor`, so the list starts after its last chat.
  final String cursor;

  const OlderChatsPage({required this.cursor});

  @override
  State<OlderChatsPage> createState() => _OlderChatsPageState();
}

class _OlderChatsPageState extends State<OlderChatsPage> with Refena {
  List<ChatDto> _chats = const [];

  /// Where the next page starts, `null` once all are loaded.
  late String? _nextCursor = widget.cursor;

  /// From the start, since the first load follows the first build.
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _loadMore();
    });
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null) {
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListChatsAction(limit: _pageSize, cursor: cursor));
      if (mounted) {
        setState(() {
          _chats = [..._chats, ...page.items];
          _nextCursor = page.nextCursor;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.chat.loadFailed(error: e.userMessage)));
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final more = _nextCursor != null;
    return Scaffold(
      appBar: AppBar(title: Text(t.base.chat.olderPage.title)),
      body: _chats.isEmpty && !more
          ? Center(child: Text(t.base.chat.noChats))
          : ListView.builder(
              key: const ValueKey('olderChats.list'),
              padding: EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom),
              // The last item loads the next page, or offers to try again.
              itemCount: _chats.length + (more ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _chats.length) {
                  final chat = _chats[index];
                  return ListTile(
                    title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatDayTime(chat.updatedAt)),
                    onTap: () async {
                      // The page's context is gone once it is closed.
                      final ref = context.ref;
                      Navigator.pop(context);
                      await ref.redux(chatProvider).dispatchAsync(OpenChatAction(chat.id));
                    },
                  );
                }
                if (_failed) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('olderChats.retry'),
                        onPressed: _loadMore,
                        icon: const Icon(Icons.refresh),
                        label: Text(t.base.common.retry),
                      ),
                    ),
                  );
                }
                if (!_loading) {
                  // Built while scrolled to the end.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_loading && !_failed) {
                      // ignore: discarded_futures
                      _loadMore();
                    }
                  });
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              },
            ),
    );
  }
}
