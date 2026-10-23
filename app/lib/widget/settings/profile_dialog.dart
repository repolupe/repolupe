import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Edits the profile of the active account: full name, first name and about, which the assistant is told.
class ProfileDialog extends StatefulWidget {
  final String fullName;
  final String firstName;
  final String about;

  const ProfileDialog({super.key, required this.fullName, required this.firstName, required this.about});

  /// Opens the dialog with the current fields (empty if none).
  static Future<void> show(
    BuildContext context, {
    required String fullName,
    required String firstName,
    required String about,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProfileDialog(fullName: fullName, firstName: firstName, about: about),
    );
  }

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> with Refena {
  bool _loading = false;
  late String _fullName = widget.fullName;
  late String _firstName = widget.firstName;
  late String _about = widget.about;

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref.global.dispatchAsync(
        UpdateProfileAction(fullName: _fullName, firstName: _firstName, about: _about),
      );
      if (!mounted) {
        return;
      }
      if (error == null) {
        Navigator.pop(context);
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
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(t.base.settings.profile.dialog.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.base.settings.profile.dialog.description,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            StringField(
              key: const ValueKey('profile.dialog.fullName'),
              value: _fullName,
              label: t.base.settings.profile.fullName,
              hint: t.base.settings.profile.dialog.fullNameHint,
              enabled: !_loading,
              autofocus: true,
              textInputAction: TextInputAction.next,
              onChanged: (value) {
                setState(() {
                  _fullName = value;
                });
              },
            ),
            const SizedBox(height: 16),
            StringField(
              key: const ValueKey('profile.dialog.firstName'),
              value: _firstName,
              label: t.base.settings.profile.firstName,
              enabled: !_loading,
              textInputAction: TextInputAction.next,
              onChanged: (value) {
                setState(() {
                  _firstName = value;
                });
              },
            ),
            const SizedBox(height: 16),
            StringField(
              key: const ValueKey('profile.dialog.about'),
              value: _about,
              label: t.base.settings.profile.about,
              hint: t.base.settings.profile.dialog.aboutPlaceholder,
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 6,
              enabled: !_loading,
              onChanged: (value) {
                setState(() {
                  _about = value;
                });
              },
            ),
            if (_error case final error?) InlineError(error, key: const ValueKey('profile.dialog.error')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(t.base.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('profile.dialog.save'),
          onPressed: _loading ? null : _save,
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
