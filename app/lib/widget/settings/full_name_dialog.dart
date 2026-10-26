import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes the full name of the active account, keeping its [firstName] and [about]. An empty full name removes it.
class FullNameDialog extends StatefulWidget {
  final String fullName;
  final String firstName;
  final String about;

  const FullNameDialog({super.key, required this.fullName, required this.firstName, required this.about});

  /// Opens the dialog with the current profile (fields empty if none).
  static Future<void> show(
    BuildContext context, {
    required String fullName,
    required String firstName,
    required String about,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => FullNameDialog(fullName: fullName, firstName: firstName, about: about),
    );
  }

  @override
  State<FullNameDialog> createState() => _FullNameDialogState();
}

class _FullNameDialogState extends State<FullNameDialog> with Refena {
  bool _loading = false;
  late String _fullName = widget.fullName;

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
          fullName: _fullName,
          firstName: widget.firstName,
          about: widget.about,
          field: ProfileField.fullName,
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
      title: Text(t.base.settings.profile.fullNameDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StringField(
            key: const ValueKey('profile.fullNameDialog.fullName'),
            value: _fullName,
            label: t.base.settings.profile.fullName,
            hint: t.base.settings.profile.fullNameDialog.hint,
            enabled: !_loading,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              setState(() {
                _fullName = value;
              });
            },
            onSubmitted: (_) async {
              if (!_loading) {
                await _save();
              }
            },
          ),
          if (_error case final error?) InlineError(error, key: const ValueKey('profile.fullNameDialog.error')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(t.base.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('profile.fullNameDialog.save'),
          onPressed: _loading ? null : _save,
          child: Text(t.base.common.save),
        ),
      ],
    );
  }
}
