import 'package:app/widget/chat/markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The selectable text of a single line [text], which is laid out on several if it doesn't fit.
RenderEditable _editable(WidgetTester tester, String text) {
  return tester.allRenderObjects.whereType<RenderEditable>().singleWhere((e) => e.text?.toPlainText() == text);
}

/// Whether [editable] shows its text on one line.
bool _isOneLine(RenderEditable editable) {
  final length = editable.text!.toPlainText().length;
  return editable.getLocalRectForCaret(TextPosition(offset: length)).top ==
      editable.getLocalRectForCaret(const TextPosition(offset: 0)).top;
}

/// Shows [table] 400 wide, filling the width.
Future<void> _pumpFillingTable(WidgetTester tester, String table) async {
  await tester.pumpWidget(
    RefenaScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 400, child: MarkdownContent(content: table, scrollTables: false)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a narrow table fills the width', (tester) async {
    await _pumpFillingTable(tester, '| A | B |\n| - | - |\n| 1 | 2 |');

    expect(tester.getSize(find.byType(Table)).width, 400);
  });

  testWidgets('a table that fits the width narrows its columns down to their longest word, not below', (tester) async {
    const date = '30.10.2026';
    await _pumpFillingTable(tester, '| Date | Tenant |\n| - | - |\n| $date | ${'word ' * 30} |');

    expect(_isOneLine(_editable(tester, date)), isTrue);
  });

  testWidgets('a table too wide at its longest words scrolls instead of being cut off', (tester) async {
    final word = 'x' * 40;
    await _pumpFillingTable(tester, '| A | B |\n| - | - |\n| $word | $word |');

    final table = tester.renderObject<RenderTable>(find.byType(Table));
    final minWidth = table.getMinIntrinsicWidth(double.infinity);
    expect(minWidth, greaterThan(400));
    expect(table.size.width, minWidth);
    final scrollView = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scrollView.controller!.position.maxScrollExtent, minWidth - 400);
  });

  // The reason for _ContentColumnWidth._caretMargin (lib/widget/chat/markdown_content.dart). Once this fails, Flutter
  // counts the caret in, and the margin can go.
  testWidgets('selectable text leaves the caret out of its minimum intrinsic width', (tester) async {
    const word = '30.10.2026';
    Future<RenderEditable> layOut({double? width}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: SizedBox(width: width, child: const SelectableText(word))),
        ),
      );
      return _editable(tester, word);
    }

    final minWidth = (await layOut()).getMinIntrinsicWidth(double.infinity);
    expect(_isOneLine(await layOut(width: minWidth)), isFalse);
    expect(_isOneLine(await layOut(width: minWidth + 3)), isTrue);
  });
}
