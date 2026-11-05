import 'package:app/widget/animated_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(double value, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedNumber(value: value, format: (value) => '$value'),
    ),
  );
}

double _shown(WidgetTester tester) => double.parse(tester.widget<Text>(find.byType(Text)).data!);

void main() {
  testWidgets('shows the initial value at once', (tester) async {
    await tester.pumpWidget(_app(100));

    expect(find.text('100.0'), findsOneWidget);
  });

  testWidgets('counts to a new value', (tester) async {
    await tester.pumpWidget(_app(100));
    await tester.pumpWidget(_app(200));

    expect(find.text('100.0'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown(tester), inExclusiveRange(100, 200));

    await tester.pumpAndSettle();
    expect(find.text('200.0'), findsOneWidget);
  });

  testWidgets('counts on from where it is to a value that comes while counting', (tester) async {
    await tester.pumpWidget(_app(100));
    await tester.pumpWidget(_app(200));
    await tester.pump(const Duration(milliseconds: 100));
    final shown = _shown(tester);

    await tester.pumpWidget(_app(300));
    expect(_shown(tester), shown);

    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown(tester), inExclusiveRange(shown, 300));

    await tester.pumpAndSettle();
    expect(find.text('300.0'), findsOneWidget);
  });

  testWidgets('shows a new value at once if animations are disabled', (tester) async {
    await tester.pumpWidget(_app(100, disableAnimations: true));
    await tester.pumpWidget(_app(200, disableAnimations: true));

    expect(find.text('200.0'), findsOneWidget);
  });
}
