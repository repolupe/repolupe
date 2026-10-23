import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// Shares a repository with the user of a user name or email.
class ShareRepositoryDialog extends StatefulWidget {
  final UuidValue repositoryId;

  const ShareRepositoryDialog({super.key, required this.repositoryId});

  /// Returns whether the repository was shared.
  static Future<bool> show(BuildContext context, {required UuidValue repositoryId}) async {
    final shared = await showDialog<bool>(
      context: context,
      builder: (_) => ShareRepositoryDialog(repositoryId: repositoryId),
    );
    return shared ?? false;
  }

  @override
  State<ShareRepositoryDialog> createState() => _ShareRepositoryDialogState();
}

class _ShareRepositoryDialogState extends State<ShareRepositoryDialog> with Refena {
  bool _loading = false;
  String _userNameOrEmail = '';

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _share() async {
    final userNameOrEmail = _userNameOrEmail.trim();
    if (userNameOrEmail.isEmpty) {
      setState(() {
        _error = t.base.repositories.shareDialog.missing;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .redux(apiProvider)
          .dispatchAsync(
            ApiAddRepositoryUserAction(
              id: widget.repositoryId,
              request: AddRepositoryUserRequest(userNameOrEmail: userNameOrEmail),
            ),
          );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on ClientError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code == ErrorCode.unknownUser ? t.base.repositories.usersCard.unknownUser : e.userMessage;
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
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(context.t.base.repositories.shareDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t.base.repositories.shareDialog.description,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          StringField(
            key: const ValueKey('repository.share.user'),
            value: _userNameOrEmail,
            label: context.t.base.user.userNameOrEmail,
            prefixIcon: const Icon(Icons.person),
            enabled: !_loading,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              setState(() {
                _userNameOrEmail = value;
              });
            },
            onSubmitted: (_) async {
              if (!_loading) {
                await _share();
              }
            },
          ),
          if (_error case final error?) InlineError(error, key: const ValueKey('repository.share.error')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: Text(context.t.base.common.cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('repository.share.confirm'),
          onPressed: _loading ? null : _share,
          icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.share),
          label: Text(context.t.base.repositories.share),
        ),
      ],
    );
  }
}
