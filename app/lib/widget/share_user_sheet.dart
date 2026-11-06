import 'package:app/gen/strings.g.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';

/// Shares something (a repository, an MCP server) with the user of a user name or email, like the web's
/// `ShareUserDialog`: [onShare] shares it and returns why it failed (`null` if it succeeded), which the sheet shows
/// and stays open then, so it can be tried again.
class ShareUserSheet extends StatefulWidget {
  final String title;
  final String description;

  /// The label of the button, e.g. "Share".
  final String shareLabel;
  final Future<String?> Function(String userNameOrEmail) onShare;

  /// The prefix of the keys of the field (`<prefix>.user`), the button (`<prefix>.confirm`) and the error
  /// (`<prefix>.error`).
  final String keyPrefix;

  const ShareUserSheet({
    super.key,
    required this.title,
    required this.description,
    required this.shareLabel,
    required this.onShare,
    required this.keyPrefix,
  });

  /// Returns whether it was shared.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String description,
    required String shareLabel,
    required Future<String?> Function(String userNameOrEmail) onShare,
    required String keyPrefix,
  }) async {
    final shared = await FormSheet.show<bool>(
      context,
      builder: (_) => ShareUserSheet(title: title, description: description, shareLabel: shareLabel, onShare: onShare, keyPrefix: keyPrefix),
    );
    return shared ?? false;
  }

  @override
  State<ShareUserSheet> createState() => _ShareUserSheetState();
}

class _ShareUserSheetState extends State<ShareUserSheet> {
  bool _loading = false;
  String _userNameOrEmail = '';

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _share() async {
    final userNameOrEmail = _userNameOrEmail.trim();
    if (userNameOrEmail.isEmpty) {
      setState(() {
        _error = t.base.user.missingUserNameOrEmail;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await widget.onShare(userNameOrEmail);
      if (!mounted) {
        return;
      }
      if (error == null) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error = error;
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
      title: Text(widget.title),
      description: widget.description,
      loading: _loading,
      onSave: _share,
      saveKey: ValueKey('${widget.keyPrefix}.confirm'),
      saveLabel: widget.shareLabel,
      saveIcon: const Icon(Icons.share),
      children: [
        StringField(
          key: ValueKey('${widget.keyPrefix}.user'),
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
        if (_error case final error?) InlineError(error, key: ValueKey('${widget.keyPrefix}.error')),
      ],
    );
  }
}
