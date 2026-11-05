import 'package:app/util/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('formatTokens abbreviates like the web, grouping the numbers a locale does not abbreviate', () {
    addTearDown(() => Intl.defaultLocale = null);
    const tokens = [850, 12345, 123456, 1234567];

    Intl.defaultLocale = 'en';
    expect(tokens.map(formatTokens), ['850', '12.3K', '123.5K', '1.2M']);

    Intl.defaultLocale = 'de';
    // with a non-breaking space
    expect(tokens.map(formatTokens), ['850', '12.345', '123.456', '1,2 Mio.']);
  });
}
