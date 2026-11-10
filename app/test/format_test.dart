import 'package:app/util/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('tokenCost charges the price per million tokens exactly', () {
    expect(tokenCost(1500, '3'), '0.0045');
    expect(tokenCost(3, '0.1'), '0.0000003');
    expect(tokenCost(2000000, '15.50'), '31');
    expect(tokenCost(1234567, '1.25'), '1.54320875');
    expect(tokenCost(0, '3'), '0');
    expect(tokenCost(1000, '0'), '0');
  });

  test('formatExactDuration has tenths of a second below a minute, rounded down', () {
    addTearDown(() => Intl.defaultLocale = null);
    const durations = [0, 99, 100, 1250, 12399, 59999, 60000, 125990];

    Intl.defaultLocale = 'en';
    expect(durations.map(formatExactDuration), ['<0.1s', '<0.1s', '0.1s', '1.2s', '12.3s', '59.9s', '1m 00s', '2m 05s']);

    Intl.defaultLocale = 'de';
    expect(formatExactDuration(12399), '12,3s');
  });

  test('formatTokens abbreviates the same in every language, localizing only the decimal separator', () {
    addTearDown(() => Intl.defaultLocale = null);
    const tokens = [0, 850, 999, 1000, 3600, 12345, 123456, 999949, 999950, 1234567, 2500000000];

    Intl.defaultLocale = 'en';
    expect(tokens.map(formatTokens), [
      '0 T.',
      '850 T.',
      '999 T.',
      '1k T.',
      '3.6k T.',
      '12.3k T.',
      '123.5k T.',
      '999.9k T.',
      '1M T.',
      '1.2M T.',
      '2.5B T.',
    ]);

    Intl.defaultLocale = 'de';
    expect(tokens.map(formatTokens), [
      '0 T.',
      '850 T.',
      '999 T.',
      '1k T.',
      '3,6k T.',
      '12,3k T.',
      '123,5k T.',
      '999,9k T.',
      '1M T.',
      '1,2M T.',
      '2,5B T.',
    ]);
  });
}
