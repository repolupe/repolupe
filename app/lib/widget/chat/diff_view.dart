import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:flutter/material.dart';

/// Vuetify's `success`, which the web's diff uses for added lines; Material has no such color.
const _addedColor = Colors.green;

/// The hunks of a diff with removed and added lines highlighted, their changed words marked. Lines never wrap: the
/// whole diff scrolls sideways, so the columns of tables stay aligned.
class DiffView extends StatelessWidget {
  final List<DiffHunkDto> hunks;

  const DiffView({super.key, required this.hunks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
      height: 1.6,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Legend(color: theme.colorScheme.error, label: context.t.base.chat.proposedCommitPanel.removed),
            const SizedBox(width: 16),
            _Legend(color: _addedColor, label: context.t.base.common.added),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ConstrainedBox(
                // The backgrounds of the lines span the box, or the longest line if it is wider.
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: IntrinsicWidth(
                  child: SelectionArea(
                    child: DefaultTextStyle.merge(
                      style: style,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final hunk in hunks) ...[
                            if (hunk.skipped) const _Gap(),
                            for (final line in hunk.lines) _Line(line: line),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Unchanged lines left out of the diff.
class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Semantics(
        label: context.t.base.chat.proposedCommitPanel.unchangedLines,
        // In the column of the signs: centered, it could be out of sight beside long lines.
        child: const Opacity(
          opacity: 0.5,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(width: 24, child: Text('⋯', textAlign: TextAlign.center)),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final DiffLineDto line;

  const _Line({required this.line});

  @override
  Widget build(BuildContext context) {
    final color = switch (line.kind) {
      DiffLineKind.removed => Theme.of(context).colorScheme.error,
      DiffLineKind.added => _addedColor,
      DiffLineKind.context || DiffLineKind.unknown => null,
    };
    final sign = switch (line.kind) {
      DiffLineKind.removed => '−',
      DiffLineKind.added => '+',
      DiffLineKind.context || DiffLineKind.unknown => '',
    };
    final text = Text.rich(
      TextSpan(
        children: [
          for (final part in line.parts)
            TextSpan(
              text: part.text,
              style: part.changed && color != null
                  ? TextStyle(
                      backgroundColor: color.withValues(alpha: 0.3),
                      decoration: line.kind == DiffLineKind.removed ? TextDecoration.lineThrough : null,
                    )
                  : null,
            ),
        ],
      ),
      softWrap: false,
    );
    return Container(
      color: color?.withValues(alpha: 0.1),
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: SizedBox(
              width: 24,
              child: Text(
                sign,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (color == null) Opacity(opacity: 0.7, child: text) else text,
        ],
      ),
    );
  }
}
