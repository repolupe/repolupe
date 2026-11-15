import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/chat/leave_temporary_dialog.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:app/widget/page_list_view.dart';
import 'package:app/widget/toned_string_field.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// How many chats are loaded at once, like the web's list.
const _pageSize = 50;

/// All chats, newest first; more are loaded when scrolled to the end. A search above them lists the matching chats
/// instead. Tapping one opens it. A long press, or the select button, selects chats to delete them.
class AllChatsPage extends StatefulWidget {
  const AllChatsPage();

  @override
  State<AllChatsPage> createState() => _AllChatsPageState();
}

class _AllChatsPageState extends State<AllChatsPage> with Refena {
  /// The text in the search field.
  String _input = '';

  /// The submitted search, `null` lists all chats.
  String? _search;

  /// Incremented by every search, so the pages still loading for the previous list are dropped.
  int _epoch = 0;

  List<ChatDto> _chats = const [];

  /// Where the next page starts, `null` for the first page.
  String? _cursor;

  bool _more = true;

  /// From the start, since the first load follows the first build.
  bool _loading = true;
  bool _failed = false;

  /// Whether tapping a chat selects it instead of opening it.
  bool _selecting = false;

  /// The selected chats, all of them listed.
  Set<UuidValue> _selected = const {};

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

  /// Lists the chats found for the search field, or all chats again if it is empty.
  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    final query = _input.trim();
    setState(() {
      _search = query.isEmpty ? null : query;
      _epoch++;
      _chats = const [];
      _cursor = null;
      _more = true;
      _loading = false;
      _failed = false;
      _selected = const {};
    });
    // ignore: discarded_futures
    _loadMore();
  }

  void _startSelecting([UuidValue? chatId]) {
    setState(() {
      _selecting = true;
      _selected = {?chatId};
    });
  }

  void _stopSelecting() {
    setState(() {
      _selecting = false;
      _selected = const {};
    });
  }

  void _toggle(UuidValue chatId) {
    setState(() {
      _selected = _selected.contains(chatId) ? ({..._selected}..remove(chatId)) : {..._selected, chatId};
    });
  }

  /// Selects the chats loaded so far, or none if all of them are.
  void _toggleAll() {
    setState(() {
      _selected = _selected.length == _chats.length ? const {} : {for (final c in _chats) c.id};
    });
  }

  Future<void> _delete() async {
    final ids = _selected.toList();
    final chats = ref.redux(chatProvider);
    final deleted = await ConfirmDialog.show(
      context,
      title: t.base.chat.allPage.deleteTitle,
      text: t.base.chat.allPage.deleteConfirm(count: ids.length),
      confirmText: t.base.common.delete,
      confirmIcon: Icons.delete,
      confirmKey: 'allChats.delete.confirm',
      onConfirm: () => chats.dispatchAsyncTakeResult(DeleteChatsAction(ids)),
    );
    if (deleted && mounted) {
      final removed = ids.toSet();
      setState(() {
        _chats = _chats.where((c) => !removed.contains(c.id)).toList();
        _selecting = false;
        _selected = const {};
      });
    }
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
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _stopSelecting();
        }
      },
      child: Scaffold(
        appBar: _selecting
            ? _SelectionAppBar(
                selected: _selected.length,
                allSelected: _chats.isNotEmpty && _selected.length == _chats.length,
                onCancel: _stopSelecting,
                onToggleAll: _chats.isEmpty ? null : _toggleAll,
                onDelete: _selected.isEmpty ? null : _delete,
              )
            : AppBar(
                title: Text(t.base.chat.allPage.title),
                actions: [
                  IconButton(
                    key: const ValueKey('allChats.select'),
                    icon: const Icon(Icons.checklist),
                    tooltip: t.base.chat.allPage.select,
                    onPressed: _chats.isEmpty ? null : _startSelecting,
                  ),
                ],
              ),
        body: PageListView.builder(
          key: const ValueKey('allChats.list'),
          padding: EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom),
          // The search, the chats, then the last item loads the next page, offers to try again, or tells there are none.
          itemCount: 1 + _chats.length + (_more || _chats.isEmpty ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TonedStringField(
                  key: const ValueKey('allChats.search'),
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
                        key: const ValueKey('allChats.clear'),
                        icon: const Icon(Icons.clear),
                        tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                        onPressed: _clear,
                      ),
                    IconButton(
                      key: const ValueKey('allChats.searchButton'),
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
              if (_selecting) {
                final selected = _selected.contains(chat.id);
                return ListTile(
                  key: ValueKey('allChats.chat.${chat.id}'),
                  leading: Checkbox(value: selected, onChanged: (_) => _toggle(chat.id)),
                  title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_subtitle(chat)),
                  selected: selected,
                  onTap: () => _toggle(chat.id),
                );
              }
              return ListTile(
                key: ValueKey('allChats.chat.${chat.id}'),
                title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_subtitle(chat)),
                onLongPress: () => _startSelecting(chat.id),
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
                child: Center(child: Text(_search == null ? t.base.chat.noChats : t.base.chat.allPage.noResults)),
              );
            }
            if (_failed) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('allChats.retry'),
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
      ),
    );
  }
}

/// When the chat was last written in, and its attachments if it has any.
String _subtitle(ChatDto chat) {
  final updated = formatDayTime(chat.updatedAt);
  if (chat.attachmentCount == 0) {
    return updated;
  }
  final attachments = t.base.chat.allPage.attachments(
    count: chat.attachmentCount,
    size: formatBytes(chat.attachmentSize),
  );
  return '$updated • $attachments';
}

/// Replaces the app bar while chats are selected.
class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selected;

  /// Whether all listed chats are selected, so the select all button deselects them.
  final bool allSelected;
  final VoidCallback onCancel;
  final VoidCallback? onToggleAll;
  final VoidCallback? onDelete;

  const _SelectionAppBar({
    required this.selected,
    required this.allSelected,
    required this.onCancel,
    required this.onToggleAll,
    required this.onDelete,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppBar(
      leading: IconButton(
        key: const ValueKey('allChats.cancelSelection'),
        icon: const Icon(Icons.close),
        tooltip: t.base.common.cancel,
        onPressed: onCancel,
      ),
      title: Text(t.base.chat.allPage.selected(count: selected)),
      actions: [
        IconButton(
          key: const ValueKey('allChats.selectAll'),
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? t.base.chat.allPage.deselectAll : t.base.chat.allPage.selectAll,
          onPressed: onToggleAll,
        ),
        IconButton(
          key: const ValueKey('allChats.delete'),
          icon: const Icon(Icons.delete_outline),
          tooltip: t.base.common.delete,
          onPressed: onDelete,
        ),
      ],
    );
  }
}
