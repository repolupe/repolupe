import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// Shares a repository with the user of a user name or email.
class ShareRepositorySheet extends StatefulWidget {
  final UuidValue repositoryId;

  const ShareRepositorySheet({super.key, required this.repositoryId});

  /// Returns whether the repository was shared.
  static Future<bool> show(BuildContext context, {required UuidValue repositoryId}) async {
    final shared = await FormSheet.show<bool>(context, builder: (_) => ShareRepositorySheet(repositoryId: repositoryId));
    return shared ?? false;
  }

  @override
  State<ShareRepositorySheet> createState() => _ShareRepositorySheetState();
}

class _ShareRepositorySheetState extends State<ShareRepositorySheet> with Refena {
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
    final t = context.t;
    return FormSheet(
      title: Text(t.base.repositories.shareDialog.title),
      description: t.base.repositories.shareDialog.description,
      loading: _loading,
      onSave: _share,
      saveKey: const ValueKey('repository.share.confirm'),
      saveLabel: t.base.repositories.share,
      saveIcon: const Icon(Icons.share),
      children: [
        StringField(
          key: const ValueKey('repository.share.user'),
          value: _userNameOrEmail,
          label: t.base.user.userNameOrEmail,
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
    );
  }
}
