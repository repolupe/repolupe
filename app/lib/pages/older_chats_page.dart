import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/chat/leave_temporary_dialog.dart';
import 'package:app/widget/page_list_view.dart';
import 'package:app/widget/toned_string_field.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// How many chats are loaded at once, like the web's list.
const _pageSize = 50;

/// The chats older than those in the drawer, newest first; more are loaded when scrolled to the end.
/// A search above them lists the matching chats of all instead. Tapping one opens it.
class OlderChatsPage extends StatefulWidget {
  /// The drawer's `nextCursor`, so the list starts after its last chat.
  final String cursor;

  const OlderChatsPage({required this.cursor});

  @override
  State<OlderChatsPage> createState() => _OlderChatsPageState();
}

class _OlderChatsPageState extends State<OlderChatsPage> with Refena {
  /// The text in the search field.
  String _input = '';

  /// The submitted search, `null` lists the older chats.
  String? _search;

  /// Incremented by every search, so the pages still loading for the previous list are dropped.
  int _epoch = 0;

  List<ChatDto> _chats = const [];

  /// Where the next page starts, `null` for the first page of a search.
  late String? _cursor = widget.cursor;

  bool _more = true;

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
    if (!_more) {
      return;
    }
    final epoch = _epoch;
    final search = _search;
    final cursor = _cursor;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final api = ref.redux(apiProvider);
      final page = search == null
          ? await api.dispatchAsyncTakeResult(ApiListChatsAction(limit: _pageSize, cursor: cursor))
          : await api.dispatchAsyncTakeResult(ApiSearchChatsAction(query: search, limit: _pageSize, cursor: cursor));
      if (mounted && epoch == _epoch) {
        setState(() {
          _chats = [..._chats, ...page.items];
          _cursor = page.nextCursor;
          _more = page.nextCursor != null;
        });
      }
    } on ClientError catch (e) {
      if (mounted && epoch == _epoch) {
        ref.global.dispatch(ShowSnackBarAction(message: t.base.chat.loadFailed(error: e.userMessage)));
        setState(() {
          _failed = true;
        });
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Lists the chats found for the search field, or the older chats again if it is empty.
  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    final query = _input.trim();
    setState(() {
      _search = query.isEmpty ? null : query;
      _epoch++;
      _chats = const [];
      _cursor = _search == null ? widget.cursor : null;
      _more = true;
      _loading = false;
      _failed = false;
    });
    // ignore: discarded_futures
    _loadMore();
  }

  void _clear() {
    setState(() {
      _input = '';
    });
    if (_search != null) {
      _submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.base.chat.olderPage.title)),
      body: PageListView.builder(
        key: const ValueKey('olderChats.list'),
        padding: EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom),
        // The search, the chats, then the last item loads the next page, offers to try again, or tells there are none.
        itemCount: 1 + _chats.length + (_more || _chats.isEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TonedStringField(
                key: const ValueKey('olderChats.search'),
                value: _input,
                onChanged: (value) {
                  setState(() {
                    _input = value;
                  });
                },
                onSubmitted: (_) => _submit(),
                hint: t.base.common.search,
                textInputAction: TextInputAction.search,
                actions: [
                  if (_input.isNotEmpty)
                    IconButton(
                      key: const ValueKey('olderChats.clear'),
                      icon: const Icon(Icons.clear),
                      tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                      onPressed: _clear,
                    ),
                  IconButton(
                    key: const ValueKey('olderChats.searchButton'),
                    icon: const Icon(Icons.search),
                    tooltip: t.base.common.search,
                    onPressed: _submit,
                  ),
                ],
              ),
            );
          }
          if (index <= _chats.length) {
            final chat = _chats[index - 1];
            return ListTile(
              title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatDayTime(chat.updatedAt)),
              onTap: () async {
                if (!await LeaveTemporaryDialog.confirm(context) || !context.mounted) {
                  return;
                }
                // The page's context is gone once it is closed.
                final ref = context.ref;
                Navigator.pop(context);
                await ref.redux(chatProvider).dispatchAsync(OpenChatAction(chat.id));
              },
            );
          }
          if (!_more) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(_search == null ? t.base.chat.noChats : t.base.chat.olderPage.noResults)),
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
