import 'package:intl/intl.dart';

/// The currencies in circulation, like `CURRENCIES` in the web (the ISO 4217 list without funds, precious metals and
/// test codes).
const currencies = [
  'AED', 'AFN', 'ALL', 'AMD', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN', 'BAM', 'BBD', 'BDT', 'BHD', 'BIF', 'BMD', //
  'BND', 'BOB', 'BRL', 'BSD', 'BTN', 'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNY', 'COP', 'CRC', //
  'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP', 'ERN', 'ETB', 'EUR', 'FJD', 'FKP', 'GBP', 'GEL', //
  'GHS', 'GIP', 'GMD', 'GNF', 'GTQ', 'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS', 'INR', 'IQD', 'IRR', //
  'ISK', 'JMD', 'JOD', 'JPY', 'KES', 'KGS', 'KHR', 'KMF', 'KPW', 'KRW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP', //
  'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR', 'MVR', 'MWK', //
  'MXN', 'MYR', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR', 'NZD', 'OMR', 'PAB', 'PEN', 'PGK', 'PHP', 'PKR', //
  'PLN', 'PYG', 'QAR', 'RON', 'RSD', 'RUB', 'RWF', 'SAR', 'SBD', 'SCR', 'SDG', 'SEK', 'SGD', 'SHP', 'SLE', //
  'SOS', 'SRD', 'SSP', 'STN', 'SVC', 'SYP', 'SZL', 'THB', 'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD', 'TWD', //
  'TZS', 'UAH', 'UGX', 'USD', 'UYU', 'UZS', 'VED', 'VES', 'VND', 'VUV', 'WST', 'XAF', 'XCD', 'XCG', 'XOF', //
  'XPF', 'YER', 'ZAR', 'ZMW', 'ZWG',
];

/// The flag emoji of an ISO 3166-1 alpha-2 code, made of its two regional indicator symbols.
String? countryFlag(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) {
    return null;
  }
  const regionalIndicatorA = 0x1F1E6;
  return String.fromCharCodes(countryCode.toUpperCase().codeUnits.map((c) => regionalIndicatorA + c - 0x41));
}

/// The flag of the currency's country (its first two letters, e.g. 🇪🇺 for EUR), like `currencyFlag` in the web.
/// `null` for supranational currencies (X..) and codes not in [currencies].
String? currencyFlag(String code) {
  if (!currencies.contains(code) || code.startsWith('X')) {
    return null;
  }
  return countryFlag(code.substring(0, 2));
}

/// E.g. `$ USD`, or just `CHF` for currencies whose symbol is their code.
String currencyLabel(String code) {
  final symbol = NumberFormat.simpleCurrency(name: code).currencySymbol;
  return symbol == code ? code : '$symbol $code';
}
