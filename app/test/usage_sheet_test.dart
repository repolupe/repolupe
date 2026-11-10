import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/usage_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _usage = UsageDto(inputTokens: 1200, outputTokens: 345, cacheReadTokens: 10000, cacheWriteTokens: 0);

/// Opens the sheet from a button, like the cost under an answer.
Future<void> _openSheet(WidgetTester tester, {CostDto? cost, String? modelName}) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => UsageSheet.show(context, usage: _usage, cost: cost, modelName: modelName),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the tokens by type and their total', (tester) async {
    await _openSheet(tester, modelName: 'Claude');

    expect(find.text('Token usage'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('10,000'), findsOneWidget);
    expect(find.text('345'), findsOneWidget);
    expect(find.text('11,545'), findsOneWidget);
  });

  testWidgets('shows the cost of each type at its price', (tester) async {
    await _openSheet(
      tester,
      cost: const CostDto(
        amount: '0.0003925',
        currency: 'USD',
        prices: TokenPricesDto(input: '0.1', output: '0.5', cacheRead: '0.01', cacheWrite: '0.125'),
      ),
    );

    // 1,200 input, 10,000 read from the cache, none written to it and 345 output tokens
    expect(find.text(r'$0.00012'), findsOneWidget);
    expect(find.text(r'$0.0001'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
    expect(find.text(r'$0.0001725'), findsOneWidget);
    expect(find.text(r'$0.0003925'), findsOneWidget);
    // Only as the column header, the total cost is in the row of the total tokens
    expect(find.text('Cost'), findsOneWidget);
  });

  testWidgets('leaves out the cost and the model when unknown', (tester) async {
    await _openSheet(tester);

    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Cost'), findsNothing);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
  });
}
