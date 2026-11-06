import 'package:app/util/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
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
