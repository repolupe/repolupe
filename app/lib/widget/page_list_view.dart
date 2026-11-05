import 'dart:math';

import 'package:flutter/material.dart';

/// The widest the content of a page gets, with its margins. Across a tablet's whole width, list tiles put their
/// chevrons and chips far from their labels, and form fields get much longer than what is typed into them. Narrower
/// than the chat's messages, whose tables and code blocks make use of the width.
const pageMaxWidth = 720.0;

/// The [ListView] of a page, which centers its content at [pageMaxWidth] on wide screens and is a plain [ListView]
/// with [padding] on phones. The list itself spans the whole width and only its padding grows, so that its scrollbar
/// stays at the screen's edge and the space beside the content scrolls it too.
class PageListView extends StatelessWidget {
  /// The padding on narrow screens. On wide ones the left and right padding grow, so the content (with this padding
  /// and its own margins, e.g. those of list tiles) is [pageMaxWidth] wide.
  final EdgeInsets padding;

  /// Builds the list with the padding for the width.
  final Widget Function(EdgeInsets padding) _list;

  PageListView({super.key, this.padding = EdgeInsets.zero, required List<Widget> children})
    : _list = ((padding) => ListView(padding: padding, children: children));

  PageListView.builder({
    super.key,
    this.padding = EdgeInsets.zero,
    required int itemCount,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) : _list = ((padding) => ListView.builder(padding: padding, itemCount: itemCount, itemBuilder: itemBuilder));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = max(0.0, (constraints.maxWidth - pageMaxWidth) / 2);
        return _list(padding + EdgeInsets.symmetric(horizontal: inset));
      },
    );
  }
}
