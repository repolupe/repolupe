import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/form_sheet.dart';
import 'package:app/widget/inline_error.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Changes one [field] of the profile of the active account, keeping the other two. An empty value removes it.
class ProfileFieldSheet extends StatefulWidget {
  final ProfileField field;
  final String fullName;
  final String firstName;
  final String about;

  const ProfileFieldSheet({super.key, required this.field, required this.fullName, required this.firstName, required this.about});

  /// Opens the sheet with the current profile (fields empty if none).
  static Future<void> show(
    BuildContext context, {
    required ProfileField field,
    required String fullName,
    required String firstName,
    required String about,
  }) async {
    await FormSheet.show<void>(
      context,
      builder: (_) => ProfileFieldSheet(field: field, fullName: fullName, firstName: firstName, about: about),
    );
  }

  @override
  State<ProfileFieldSheet> createState() => _ProfileFieldSheetState();
}

class _ProfileFieldSheetState extends State<ProfileFieldSheet> with Refena {
  bool _loading = false;
  late String _value = switch (widget.field) {
    ProfileField.fullName => widget.fullName,
    ProfileField.firstName => widget.firstName,
    ProfileField.about => widget.about,
  };

  /// Why the last try failed, until the next one.
  String? _error;

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final field = widget.field;
      final error = await ref.global.dispatchAsync(
        UpdateProfileAction(
          fullName: field == ProfileField.fullName ? _value : widget.fullName,
          firstName: field == ProfileField.firstName ? _value : widget.firstName,
          about: field == ProfileField.about ? _value : widget.about,
          field: field,
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
    final profile = context.t.base.settings.profile;
    // The keys are grouped like the texts.
    final (title, label, hint, keyPrefix) = switch (widget.field) {
      ProfileField.fullName => (profile.fullNameDialog.title, profile.fullName, profile.fullNameDialog.hint, 'profile.fullNameDialog'),
      ProfileField.firstName => (profile.firstNameDialog.title, profile.firstName, null, 'profile.firstNameDialog'),
      ProfileField.about => (profile.aboutDialog.title, profile.about, profile.aboutDialog.placeholder, 'profile.aboutDialog'),
    };
    final multiline = widget.field == ProfileField.about;
    return FormSheet(
      title: Text(title),
      loading: _loading,
      onSave: _save,
      saveKey: ValueKey('$keyPrefix.save'),
      children: [
        StringField(
          key: ValueKey('$keyPrefix.${widget.field.name}'),
          value: _value,
          label: label,
          hint: hint,
          keyboardType: multiline ? TextInputType.multiline : null,
          minLines: multiline ? 3 : null,
          maxLines: multiline ? 6 : 1,
          enabled: !_loading,
          autofocus: true,
          textInputAction: multiline ? null : TextInputAction.done,
          onChanged: (value) {
            setState(() {
              _value = value;
            });
          },
          onSubmitted: multiline
              ? null
              : (_) async {
                  if (!_loading) {
                    await _save();
                  }
                },
        ),
        if (_error case final error?) InlineError(error, key: ValueKey('$keyPrefix.error')),
      ],
    );
  }
}
