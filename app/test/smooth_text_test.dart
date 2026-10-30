import 'package:app/widget/chat/smooth_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(String text, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SmoothText(
        text: text,
        builder: (context, text, revealing) => Text('$text|$revealing'),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the initial text at once', (tester) async {
    await tester.pumpWidget(_app('Hello'));

    expect(find.text('Hello|false'), findsOneWidget);
  });

  testWidgets('reveals appended text gradually', (tester) async {
    await tester.pumpWidget(_app('Hello'));
    await tester.pumpWidget(_app('Hello, world'));

    expect(find.text('Hello|true'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    final shown = tester.widget<Text>(find.byType(Text)).data!;
    expect(shown.length, inExclusiveRange('Hello|true'.length, 'Hello, world|true'.length));

    await tester.pumpAndSettle();
    expect(find.text('Hello, world|false'), findsOneWidget);
  });

  testWidgets('shows a change other than an append at once', (tester) async {
    await tester.pumpWidget(_app('Hello'));
    await tester.pumpWidget(_app('Bye'));

    expect(find.text('Bye|false'), findsOneWidget);
  });

  testWidgets('shows appended text at once if animations are disabled', (tester) async {
    await tester.pumpWidget(_app('Hello', disableAnimations: true));
    await tester.pumpWidget(_app('Hello, world', disableAnimations: true));

    expect(find.text('Hello, world|false'), findsOneWidget);
  });
}
