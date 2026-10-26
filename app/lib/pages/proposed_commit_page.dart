import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/util/tool_call.dart';
import 'package:app/widget/chat/diff_view.dart';
import 'package:app/widget/chat/tool_call_info.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The commit a `change_file`, `move_files` or `save_attachment` call proposed, as its diff or its moves, with a button
/// to push it to the branch unless it already was.
class ProposedCommitPage extends StatefulWidget {
  final UuidValue chatId;
  final ToolCallSummaryDto toolCall;

  /// The file it changes, or where the first move goes to.
  final String path;

  const ProposedCommitPage({super.key, required this.chatId, required this.toolCall, required this.path});

  @override
  State<ProposedCommitPage> createState() => _ProposedCommitPageState();
}

class _ProposedCommitPageState extends State<ProposedCommitPage> with Refena {
  FileDiffDto? _diff;

  /// Whether it was committed, loaded with the diff.
  ProposedCommitDto? _change;
  String? _error;
  bool _loading = true;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    ensureRef((_) => _load());
  }

  Future<void> _load() async {
    final api = ref.redux(apiProvider);
    try {
      final (diff, change) = await (
        api.dispatchAsyncTakeResult(ApiGetProposedCommitDiffAction(chatId: widget.chatId, toolCallId: widget.toolCall.id)),
        api.dispatchAsyncTakeResult(ApiGetProposedCommitAction(chatId: widget.chatId, toolCallId: widget.toolCall.id)),
      ).wait;
      if (mounted) {
        setState(() {
          _diff = diff;
          _change = change;
        });
      }
    } on ParallelWaitError<(FileDiffDto?, ProposedCommitDto?), (AsyncError?, AsyncError?)> catch (e) {
      final error = e.errors.$1?.error ?? e.errors.$2?.error;
      if (error is! ClientError) {
        rethrow;
      }
      if (mounted) {
        setState(() => _error = error.userMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Pushes the change and closes the page once it is on the branch; a conflict or a failed push is shown instead.
  Future<void> _commit() async {
    setState(() => _committing = true);
    final ProposedCommitDto committed;
    try {
      committed = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(ApiCommitProposedCommitAction(chatId: widget.chatId, toolCallId: widget.toolCall.id));
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.chat.proposedCommitPanel.applyFailed(error: e.userMessage)));
      if (mounted) {
        setState(() => _committing = false);
      }
      return;
    }

    if (committed.status == ProposedCommitStatus.committed) {
      final path = committed.path;
      ref.global.dispatch(
        ShowSnackBarAction(
          message: path == null ? t.base.chat.proposedCommitPanel.appliedMoves : t.base.chat.proposedCommitPanel.appliedTo(name: fileName(path)),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    if (mounted) {
      setState(() {
        _change = committed;
        _committing = false;
      });
    }
  }

  /// Turns on the user's `autoCommit`, which applies the changes of later answers, and commits this one.
  Future<void> _enableAutoCommit() async {
    final enabled = await ConfirmDialog.show(
      context,
      title: t.base.chat.proposedCommitPanel.autoCommitTitle,
      text: t.base.chat.proposedCommitPanel.autoCommitText,
      confirmText: t.base.chat.proposedCommitPanel.autoCommitConfirm,
      confirmIcon: Icons.check_circle,
      confirmKey: 'proposedCommit.autoCommit.confirm',
      onConfirm: () async {
        try {
          await ref.redux(apiProvider).dispatchAsync(ApiSetAutoCommitAction(autoCommit: true));
        } on ClientError catch (e) {
          return t.base.settings.preferences.page.autoCommitSaveFailed(error: e.userMessage);
        }
        await ref.redux(meProvider).dispatchAsync(RefreshMeAction());
        return null;
      },
    );
    if (enabled && mounted) {
      await _commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch(meProvider);
    final moves = widget.toolCall.moves;
    final lines = switch (widget.toolCall.inputMap['message']) {
      final String message => message.trim().split('\n'),
      _ => const [''],
    };
    final message = lines.first;
    final body = lines.skip(1).join('\n').trim();
    final diff = _diff;
    final change = _change;
    final applied = change?.status == ProposedCommitStatus.committed;

    return ToolCallFileScaffold(
      toolCall: widget.toolCall,
      // The moves are in the diff, the destination of the first would be misleading.
      path: moves.length > 1 ? '' : widget.path,
      title: message.isNotEmpty ? message : (moves.length > 1 ? context.t.base.chat.moveCount(count: moves.length) : null),
      loading: _loading,
      error: _error,
      footer: change == null || applied
          ? null
          : _CommitBar(
              change: change,
              committing: _committing,
              onCommit: _commit,
              onEnableAutoCommit: change.canCommit && change.status == ProposedCommitStatus.proposed && user != null && !user.autoCommit
                  ? _enableAutoCommit
                  : null,
            ),
      child: diff == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (body.isNotEmpty) ...[
                  Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                ],
                if (applied) ...[
                  Chip(
                    avatar: Icon(Icons.check, color: theme.colorScheme.primary),
                    label: Text(context.t.base.chat.proposedCommitPanel.applied),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(height: 12),
                ],
                if (change?.error case final error?) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      // A conflict is resolved by asking for the change again, not an error of the app.
                      color: change!.status == ProposedCommitStatus.conflict ? theme.colorScheme.tertiaryContainer : theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      error,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: change.status == ProposedCommitStatus.conflict
                            ? theme.colorScheme.onTertiaryContainer
                            : theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (diff.moves case final moves?)
                  _Moves(moves: moves)
                else if (!applied && (diff.kind == DiffFileKind.added || diff.kind == DiffFileKind.deleted)) ...[
                  _Notice(
                    deleted: diff.kind == DiffFileKind.deleted,
                  ),
                  const SizedBox(height: 12),
                ],
                if (diff.hunks.isNotEmpty)
                  DiffView(hunks: diff.hunks)
                else if (diff.kind != DiffFileKind.deleted && diff.moves == null)
                  Text(
                    context.t.base.chat.proposedCommitPanel.noPreview,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
    );
  }
}

/// That the change creates or deletes the file.
class _Notice extends StatelessWidget {
  final bool deleted;

  const _Notice({required this.deleted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = deleted
        ? (theme.colorScheme.tertiaryContainer, theme.colorScheme.onTertiaryContainer)
        : (theme.colorScheme.secondaryContainer, theme.colorScheme.onSecondaryContainer);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(deleted ? Icons.delete_outline : Icons.note_add_outlined, size: 20, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              deleted ? context.t.base.chat.proposedCommitPanel.willDelete : context.t.base.chat.proposedCommitPanel.willCreate,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where each file or folder moves to, with the number of files in a folder.
class _Moves extends StatelessWidget {
  final List<DiffMoveDto> moves;

  const _Moves({required this.moves});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']);
    final caption = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        for (final move in moves)
          Semantics(
            label: context.t.base.chat.proposedCommitPanel.movedTo(from: move.from, to: move.to),
            excludeSemantics: true,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(move.from, style: mono),
                Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.onSurfaceVariant),
                Text(move.to, style: mono),
                if (move.folderFiles case final count?)
                  Text(context.t.base.chat.proposedCommitPanel.folderFiles(count: count.toInt()), style: caption),
              ],
            ),
          ),
      ],
    );
  }
}

/// Why the change can't be applied, or the button that applies it (again, after a conflict or a failed push).
class _CommitBar extends StatelessWidget {
  final ProposedCommitDto change;
  final bool committing;
  final VoidCallback onCommit;

  /// Shows the button that turns on auto-commit, unless `null`.
  final VoidCallback? onEnableAutoCommit;

  const _CommitBar({required this.change, required this.committing, required this.onCommit, required this.onEnableAutoCommit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final hint = !change.canCommit
        ? context.t.base.chat.proposedCommitPanel.cannotCommit
        // No room for it next to both buttons.
        : change.status == ProposedCommitStatus.proposed && onEnableAutoCommit == null
        ? context.t.flutter.chat.proposedCommitPage.notApplied
        : null;
    // Wraps if the labels are too long for one line (e.g. in German).
    final buttons = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        if (onEnableAutoCommit case final onEnableAutoCommit?)
          TextButton(
            onPressed: committing ? null : onEnableAutoCommit,
            child: Text(context.t.base.chat.proposedCommitPanel.enableAutoCommit),
          ),
        if (change.canCommit)
          FilledButton.icon(
            icon: committing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                  )
                : const Icon(Icons.check),
            label: Text(
              change.status == ProposedCommitStatus.proposed
                  ? context.t.base.chat.proposedCommitPanel.apply
                  : context.t.base.chat.proposedCommitPanel.tryAgain,
            ),
            onPressed: committing ? null : onCommit,
          ),
      ],
    );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: hint == null
                ? SizedBox(width: double.infinity, child: buttons)
                : Row(
                    children: [
                      Expanded(child: Text(hint, style: caption)),
                      if (change.canCommit) ...[
                        const SizedBox(width: 12),
                        buttons,
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
