import 'package:app/gen/strings.g.dart';
import 'package:flutter/material.dart';

/// A form in a bottom sheet: [title], [description], the [children] (its fields, with an `InlineError` of the last
/// try), an [extraAction] (such as removing the value) and Cancel and Save at the bottom. It stays above the keyboard,
/// and while [loading] the buttons are disabled and the back button and taps outside don't close it.
class FormSheet extends StatelessWidget {
  final Widget title;
  final String? description;
  final List<Widget> children;

  final Widget? extraAction;
  final bool loading;

  /// Saves the form, `null` disables Save.
  final VoidCallback? onSave;
  final Key? saveKey;

  /// The label of Save, [saveIcon] its icon (replaced by a progress indicator while [loading]).
  final String? saveLabel;
  final Widget? saveIcon;

  const FormSheet({
    super.key,
    required this.title,
    this.description,
    required this.children,
    this.extraAction,
    required this.loading,
    required this.onSave,
    this.saveKey,
    this.saveLabel,
    this.saveIcon,
  });

  /// Opens the sheet [builder] builds. Dragging closes it even while it can't be popped, so a sheet whose save must
  /// not be left running passes `enableDrag: false` (which also hides the drag handle).
  static Future<T?> show<T>(BuildContext context, {required WidgetBuilder builder, bool enableDrag = true}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: enableDrag,
      showDragHandle: enableDrag,
      // Without the drag handle, the space it takes.
      builder: enableDrag ? builder : (context) => Padding(padding: const EdgeInsets.only(top: 24), child: builder(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final label = saveLabel ?? t.base.common.save;
    const progress = SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
    return PopScope(
      canPop: !loading,
      child: Padding(
        // Keeps the fields above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DefaultTextStyle.merge(style: theme.textTheme.titleMedium, child: title),
                    if (description case final description?) ...[
                      const SizedBox(height: 8),
                      Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 20),
                    ...children,
                    if (extraAction case final extraAction?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(alignment: Alignment.centerLeft, child: extraAction),
                      ),
                  ],
                ),
              ),
              Padding(
                // useSafeArea only covers the top.
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.paddingOf(context).bottom),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: loading ? null : () => Navigator.pop(context),
                      child: Text(t.base.common.cancel),
                    ),
                    if (saveIcon case final saveIcon?)
                      FilledButton.icon(
                        key: saveKey,
                        onPressed: loading ? null : onSave,
                        icon: loading ? progress : saveIcon,
                        label: Text(label),
                      )
                    else
                      FilledButton(
                        key: saveKey,
                        onPressed: loading ? null : onSave,
                        // The hidden label keeps the button's width, so Cancel doesn't move.
                        child: loading
                            ? Stack(
                                alignment: Alignment.center,
                                children: [
                                  Opacity(opacity: 0, child: Text(label)),
                                  progress,
                                ],
                              )
                            : Text(label),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
