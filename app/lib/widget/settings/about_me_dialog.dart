import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the about text of the active account, keeping its [fullName] and [firstName]. An empty text removes it.
class AboutMeDialog extends StatefulWidget {
  final String fullName;
  final String firstName;
  final String about;

  const AboutMeDialog({super.key, required this.fullName, required this.firstName, required this.about});

  /// Opens the dialog with the current profile (fields empty if none).
  static Future<void> show(
    BuildContext context, {
    required String fullName,
    required String firstName,
    required String about,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AboutMeDialog(fullName: fullName, firstName: firstName, about: about),
    );
  }

  @override
  State<AboutMeDialog> createState() => _AboutMeDialogState();
}

class _AboutMeDialogState extends State<AboutMeDialog> with Refena {
  bool _loading = false;
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
        UpdateProfileAction(
          fullName: widget.fullName,
          firstName: widget.firstName,
          about: _about,
          field: ProfileField.about,
        ),
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
    return AlertDialog(
      title: Text(t.base.settings.profile.aboutDialog.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StringField(
              key: const ValueKey('profile.aboutDialog.about'),
              value: _about,
              label: t.base.settings.profile.about,
              hint: t.base.settings.profile.aboutDialog.placeholder,
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 6,
              enabled: !_loading,
              autofocus: true,
              onChanged: (value) {
                setState(() {
                  _about = value;
                });
              },
            ),
            if (_error case final error?) InlineError(error, key: const ValueKey('profile.aboutDialog.error')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(t.base.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('profile.aboutDialog.save'),
          onPressed: _loading ? null : _save,
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
