import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/util/format.dart';
import 'package:app/widget/confirm_dialog.dart';
import 'package:app/widget/repositories/info_card.dart';
import 'package:app/widget/repositories/share_repository_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The users a repository is shared with, for its owner or an admin: share it with another user, let a user
/// commit the proposed changes (if the repository allows commits), or stop sharing it.
class RepositoryUsersCard extends StatefulWidget {
  final UuidValue repositoryId;

  /// Users can only commit to repositories that allow commits.
  final bool allowCommits;

  /// A local repository has no access token, its commits only move the branch on the server.
  final bool local;

  const RepositoryUsersCard({super.key, required this.repositoryId, required this.allowCommits, required this.local});

  @override
  State<RepositoryUsersCard> createState() => _RepositoryUsersCardState();
}

class _RepositoryUsersCardState extends State<RepositoryUsersCard> with Refena {
  /// `null` until loaded.
  List<RepositoryUserDto>? _users;

  /// From the start, since the first load follows the first build.
  bool _loading = true;

  /// The user whose write access is being changed.
  UuidValue? _updating;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final users = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListRepositoryUsersAction(id: widget.repositoryId));
      if (mounted) {
        setState(() {
          _users = users;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.usersCard.loadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _share() async {
    final shared = await ShareRepositorySheet.show(context, repositoryId: widget.repositoryId);
    if (!shared || !mounted) {
      return;
    }
    ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.usersCard.shared));
    await _load();
  }

  Future<void> _setCanCommit(RepositoryUserDto user, bool canCommit) async {
    setState(() {
      _updating = user.userId;
    });
    try {
      await ref
          .redux(apiProvider)
          .dispatchAsync(
            ApiUpdateRepositoryUserAction(
              id: widget.repositoryId,
              userId: user.userId,
              request: UpdateRepositoryUserRequest(canCommit: canCommit),
            ),
          );
      if (mounted) {
        setState(() {
          _users = [
            for (final u in _users ?? const <RepositoryUserDto>[])
              u.userId == user.userId
                  ? RepositoryUserDto(userId: u.userId, userName: u.userName, email: u.email, canCommit: canCommit, createdAt: u.createdAt)
                  : u,
          ];
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.usersCard.canCommitFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _updating = null;
        });
      }
    }
  }

  Future<void> _remove(RepositoryUserDto user) async {
    final removed = await ConfirmDialog.show(
      context,
      title: t.base.repositories.usersCard.stopSharingTitle,
      text: t.base.repositories.usersCard.stopSharingText(name: user.userName),
      confirmText: t.base.repositories.usersCard.stopSharing,
      confirmIcon: Icons.person_remove,
      confirmKey: 'repository.users.remove.confirm',
      onConfirm: () async {
        try {
          await ref.redux(apiProvider).dispatchAsync(ApiRemoveRepositoryUserAction(id: widget.repositoryId, userId: user.userId));
          return null;
        } on ClientError catch (e) {
          return t.base.repositories.usersCard.stopFailed(error: e.userMessage);
        }
      },
    );
    if (!removed || !mounted) {
      return;
    }
    ref.global.dispatch(ShowSnackBarAction(message: t.base.repositories.usersCard.stopped));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final users = _users;
    final usersCard = context.t.base.repositories.usersCard;
    return InfoCard(
      icon: Icons.group_outlined,
      title: usersCard.title,
      actions: [
        FilledButton.icon(
          key: const ValueKey('repository.users.share'),
          onPressed: users == null ? null : _share,
          icon: const Icon(Icons.share),
          label: Text(context.t.base.repositories.share),
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            widget.local ? usersCard.descriptionLocal : usersCard.description,
            style: muted,
          ),
        ),
        if (users == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('repository.users.retry'),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.t.base.common.retry),
                    ),
                  ),
          )
        else if (users.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(usersCard.notShared, style: muted),
          )
        else
          for (final (i, user) in users.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              key: ValueKey('repository.users.${user.userId}'),
              leading: const Icon(Icons.person),
              title: Text(user.userName),
              subtitle: Tooltip(
                message: formatDateTime(user.createdAt),
                child: Text(
                  [?user.email, context.t.flutter.repositories.usersCard.sharedRelative(relative: formatRelative(user.createdAt))].join('\n'),
                ),
              ),
              isThreeLine: user.email != null,
              trailing: IconButton(
                key: ValueKey('repository.users.remove.${user.userId}'),
                tooltip: usersCard.stopSharing,
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: () => _remove(user),
              ),
            ),
            SwitchListTile(
              key: ValueKey('repository.users.canCommit.${user.userId}'),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: Text(usersCard.canCommit),
              subtitle: Text(widget.allowCommits ? context.t.flutter.repositories.usersCard.canCommitOn : usersCard.canCommitOff),
              value: user.canCommit,
              onChanged: widget.allowCommits && _updating == null ? (value) => _setCanCommit(user, value) : null,
            ),
          ],
      ],
    );
  }
}
