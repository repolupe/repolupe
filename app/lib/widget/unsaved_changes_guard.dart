import 'package:app/gen/strings.g.dart';
import 'package:flutter/material.dart';

/// Asks before leaving a form page with unsaved changes ([dirty]) by the back button or gesture; the page closes
/// only if the user discards them. Saving pops with `Navigator.pop`, which is not held up.
class UnsavedChangesGuard extends StatelessWidget {
  final bool dirty;
  final Widget child;

  const UnsavedChangesGuard({super.key, required this.dirty, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.t.flutter.common.unsavedChanges.title),
            content: Text(context.t.flutter.common.unsavedChanges.text),
            actions: [
              TextButton(
                key: const ValueKey('unsavedChanges.keepEditing'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.t.flutter.common.unsavedChanges.keepEditing),
              ),
              FilledButton(
                key: const ValueKey('unsavedChanges.discard'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.t.flutter.common.unsavedChanges.discard),
              ),
            ],
          ),
        );
        if ((discard ?? false) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: child,
    );
  }
}
