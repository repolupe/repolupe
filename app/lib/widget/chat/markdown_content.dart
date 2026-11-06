import 'dart:math';

import 'package:app/gen/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger = Logger('MarkdownContent');

/// The link schemes that open when tapped, others (e.g. app-specific ones) are ignored, since answers are written by the model.
const _linkSchemes = {'http', 'https', 'mailto', 'tel'};

/// Links open outside the app. A table's columns are as wide as their content, and a wide table scrolls sideways,
/// unless [scrollTables] is off.
class MarkdownContent extends StatelessWidget {
  final String content;

  /// The space to the left and right of the blocks. A wide table scrolls through it, so that it reaches the edges
  /// rather than being cut off where the text ends.
  final double horizontalPadding;

  /// Whether a wide table scrolls sideways. Otherwise every table fills the width, each column as wide as its content
  /// plus an equal share of the rest, or, if the table is too wide, narrowed down to its longest word.
  final bool scrollTables;

  const MarkdownContent({super.key, required this.content, this.horizontalPadding = 0, this.scrollTables = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
      backgroundColor: Colors.transparent,
    );
    final codeBackground = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    );
    final ref = context.ref;
    return _MarkdownBody(
      horizontalPadding: horizontalPadding,
      scrollTables: scrollTables,
      data: content,
      selectable: true,
      onTapLink: (_, href, _) async {
        if (href != null) {
          await _openLink(ref, href);
        }
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge,
        a: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
        listBullet: theme.textTheme.bodyLarge,
        code: code,
        codeblockDecoration: codeBackground,
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 4)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        tableColumnWidth: const _ContentColumnWidth(),
      ),
    );
  }
}

/// A [MarkdownBody] with [horizontalPadding] at the sides of its blocks, which its tables scroll through if
/// [scrollTables] is on, and otherwise fill.
class _MarkdownBody extends MarkdownBody {
  final double horizontalPadding;
  final bool scrollTables;

  const _MarkdownBody({
    required this.horizontalPadding,
    required this.scrollTables,
    required super.data,
    super.selectable,
    super.onTapLink,
    super.styleSheet,
  });

  @override
  Widget build(BuildContext context, List<Widget>? children) {
    final padding = EdgeInsets.symmetric(horizontal: horizontalPadding);
    Widget padded(Widget child) => horizontalPadding > 0 ? Padding(padding: padding, child: child) : child;
    return super.build(context, [
      for (final block in children ?? const <Widget>[])
        if (!_isTable(block))
          padded(block)
        else if (scrollTables)
          _ScrollingTable(padding: padding, child: block)
        else
          // Since no column flexes, Table gives each an equal share of the width it must fill beyond its content.
          padded(SizedBox(width: double.infinity, child: block)),
    ]);
  }
}

/// Whether [block] is a table, which flutter_markdown_plus clips to its border's radius.
bool _isTable(Widget block) => block is Table || (block is ClipRRect && block.child is Table);

/// Sizes a column like [IntrinsicColumnWidth]: as wide as its content, or, if the table has to fit, down to its longest
/// word. Not an [IntrinsicColumnWidth], since flutter_markdown_plus would then scroll every table itself, inside the
/// padding. A table in a list or quote, which [_MarkdownBody] doesn't see, fits the width this way, but doesn't fill it.
class _ContentColumnWidth extends TableColumnWidth {
  static const _intrinsic = IntrinsicColumnWidth();

  /// The space for the caret, which selectable text (a [RenderEditable]) takes off the width it is laid out in, but
  /// leaves out of its minimum intrinsic width: a gap of 1 and [SelectableText.cursorWidth]. Without it, the longest
  /// word of a column at its minimum width breaks before its last letter. A Flutter bug, which
  /// test/markdown_content_test.dart notices the fix of.
  static const _caretMargin = 1.0 + 2.0;

  const _ContentColumnWidth();

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) => min(
    _intrinsic.minIntrinsicWidth(cells, containerWidth) + _caretMargin,
    _intrinsic.maxIntrinsicWidth(cells, containerWidth),
  );

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) => _intrinsic.maxIntrinsicWidth(cells, containerWidth);
}

/// A table that scrolls sideways when it is wider than the space, with the padding scrolling along.
class _ScrollingTable extends StatefulWidget {
  final EdgeInsets padding;
  final Widget child;

  const _ScrollingTable({required this.padding, required this.child});

  @override
  State<_ScrollingTable> createState() => _ScrollingTableState();
}

class _ScrollingTableState extends State<_ScrollingTable> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}

/// Opens [href] in the app that handles it (e.g. the browser), or shows a snack bar if it cannot.
Future<void> _openLink(Ref ref, String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null || !_linkSchemes.contains(uri.scheme.toLowerCase())) {
    _logger.info('Ignoring the link $href');
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException catch (e) {
    _logger.warning('Cannot open $uri: $e');
  }
  if (!opened) {
    ref.global.dispatch(ShowSnackBarAction(message: t.flutter.chat.markdownContent.openLinkFailed(link: href)));
  }
}
