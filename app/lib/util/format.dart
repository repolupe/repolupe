import 'dart:math';

import 'package:app/gen/strings.g.dart';
import 'package:intl/intl.dart';

/// E.g. `$0.03`, rounded to the currency's minor unit. Costs below it keep one significant digit, e.g. `$0.0003`
/// instead of `$0.00`.
String formatCost(String amount, String currency) {
  final value = double.tryParse(amount);
  if (value == null) {
    return '$amount $currency';
  }
  final format = NumberFormat.simpleCurrency(name: currency);
  final smallest = pow(10, -(format.decimalDigits ?? 2)).toDouble();
  if (value > 0 && value < smallest) {
    // the exponent of the value rounded to one significant digit, e.g. `-4` for `3e-4`
    // (intl's maximumSignificantDigits is capped by the currency's decimals)
    final exponent = int.parse(value.toStringAsExponential(0).split('e').last);
    return NumberFormat.simpleCurrency(name: currency, decimalDigits: -exponent).format(value);
  }
  return format.format(value);
}

/// E.g. `$0.004125`, with all the decimals of the amount (but at least those of the currency's minor unit).
String formatExactCost(String amount, String currency) {
  final value = double.tryParse(amount);
  if (value == null) {
    return '$amount $currency';
  }
  final decimals = amount.contains('.') ? amount.split('.').last.length : 0;
  final minimum = NumberFormat.simpleCurrency(name: currency).decimalDigits ?? 2;
  return NumberFormat.simpleCurrency(name: currency, decimalDigits: max(decimals, minimum)).format(value);
}

/// What [tokens] cost at [price] per million tokens, both as the API gives them, as an exact decimal string without
/// trailing zeros, e.g. `0.0045` for 1,500 tokens at `3` (like the web's).
String tokenCost(int tokens, String price) {
  final [whole, ...rest] = price.split('.');
  final fraction = rest.firstOrNull ?? '';
  // a million is 6 more decimals
  final scale = fraction.length + 6;
  final digits = (BigInt.from(tokens) * BigInt.parse('$whole$fraction')).toString().padLeft(scale + 1, '0');
  final exact = '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
  return exact.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// E.g. `42s` or `3m 05s`.
String formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) {
    return t.base.chat.assistantMessage.durationSeconds(seconds: seconds);
  }
  return t.base.chat.assistantMessage.durationMinutes(minutes: seconds ~/ 60, seconds: (seconds % 60).toString().padLeft(2, '0'));
}

/// With tenths of a second below a minute, e.g. `12.3s` or `<0.1s`, and else whole seconds, e.g. `2m 05s`. Rounded down
/// like [formatDuration], so that a total matches the duration below the answer (like the web's).
String formatExactDuration(int milliseconds) {
  String seconds(double value) => t.base.chat.assistantMessage.durationSeconds(seconds: NumberFormat('0.0').format(value));
  if (milliseconds < 100) {
    return t.base.chat.durationDialog.lessThan(duration: seconds(0.1));
  }
  if (milliseconds < 60000) {
    return seconds((milliseconds ~/ 100) / 10);
  }
  return formatDuration(Duration(milliseconds: milliseconds));
}

/// Output tokens per second, e.g. `1,234.5`.
String formatSpeed(double tokensPerSecond) => NumberFormat('#,##0.#').format(tokensPerSecond);

/// E.g. `12,345`.
String formatCount(int count) => NumberFormat.decimalPattern().format(count);

/// E.g. `850 T.`, `3.6k T.` or `1.2M T.`, the same in every language except for the decimal separator (like the web's).
String formatTokens(int tokens) {
  const units = ['', 'k', 'M', 'B'];
  var exponent = 0;
  // the next unit as soon as the value would round to 1000, e.g. `1M` rather than `1000k`
  while (exponent < units.length - 1 && tokens.abs() / pow(1000, exponent) >= 999.95) {
    exponent++;
  }
  final value = NumberFormat('#,##0.#').format(tokens / pow(1000, exponent));
  return '$value${units[exponent]} T.';
}

/// E.g. `Oct 21, 2026 2:05 PM`, in the device's time zone.
String formatDateTime(DateTime dateTime) => DateFormat.yMMMd().add_jm().format(dateTime.toLocal());

/// E.g. `Today • 3:45 PM`, `Yesterday • 3:45 PM`, `Oct 21 • 3:45 PM` or `Oct 21, 2025 • 3:45 PM`, in the device's time zone.
String formatDayTime(DateTime dateTime, {DateTime? now}) {
  final local = dateTime.toLocal();
  final current = now ?? DateTime.now();
  // UTC, so a day changing to or from daylight saving time still counts as one.
  final today = DateTime.utc(current.year, current.month, current.day);
  final day = DateTime.utc(local.year, local.month, local.day);
  final labels = t.flutter.format.day;
  final dayLabel = switch (today.difference(day).inDays) {
    0 => labels.today,
    1 => labels.yesterday,
    _ => day.year == today.year ? DateFormat.MMMd().format(local) : DateFormat.yMMMd().format(local),
  };
  return '$dayLabel • ${DateFormat.jm().format(local)}';
}

/// E.g. `1.2 MB` with decimal units like GitLab and Forgejo, `-` for `null` (before the first sync).
String formatBytes(int? bytes) {
  if (bytes == null) {
    return '-';
  }
  const units = ['B', 'kB', 'MB', 'GB', 'TB'];
  final exponent = min((log(max(bytes, 1)) / ln10 / 3).floor(), units.length - 1);
  final value = bytes / pow(1000, exponent);
  return '${NumberFormat(exponent == 0 ? '#,##0' : '#,##0.#').format(value)} ${units[exponent]}';
}

/// E.g. `5 minutes ago`, `in 2 hours`, `just now`, or `-` for `null`.
String formatRelative(DateTime? dateTime, {DateTime? now}) {
  if (dateTime == null) {
    return '-';
  }
  final seconds = dateTime.difference(now ?? DateTime.now()).inSeconds;
  final past = seconds < 0;
  final abs = seconds.abs();
  final relative = t.flutter.format.relative;
  if (abs < 45) {
    return relative.justNow;
  }
  return switch (abs) {
    >= 86400 => past ? relative.daysAgo(count: (abs / 86400).round()) : relative.inDays(count: (abs / 86400).round()),
    >= 3600 => past ? relative.hoursAgo(count: (abs / 3600).round()) : relative.inHours(count: (abs / 3600).round()),
    _ => past ? relative.minutesAgo(count: (abs / 60).round()) : relative.inMinutes(count: (abs / 60).round()),
  };
}

/// The first 7 characters of a commit sha, `-` for `null`.
String shortSha(String? sha) => sha == null ? '-' : sha.substring(0, min(7, sha.length));

/// The choices of a repository's sync interval in seconds (the API requires at least 60) with their labels.
List<(int, String)> get pollIntervalOptions {
  final labels = t.base.repositories.pollInterval;
  return [
    (60, labels.minute),
    (300, labels.minutes5),
    (900, labels.minutes15),
    (3600, labels.hour),
    (21600, labels.hours6),
    (86400, labels.daily),
  ];
}

/// E.g. `Every 15 minutes`, or `Every 42 seconds` for a value that is not one of [pollIntervalOptions].
String formatPollInterval(int seconds) {
  return pollIntervalOptions.where((o) => o.$1 == seconds).firstOrNull?.$2 ?? t.base.repositories.pollInterval.seconds(seconds: seconds);
}

/// A price per million tokens, e.g. `$3.00` or `$0.000125` (up to 6 decimals, at least the currency's usual ones).
String formatPrice(String price, String currency) {
  final value = double.tryParse(price);
  if (value == null) {
    return '$price $currency';
  }
  final format = NumberFormat.simpleCurrency(name: currency)
    ..minimumFractionDigits = NumberFormat.simpleCurrency(name: currency).decimalDigits ?? 2
    ..maximumFractionDigits = 6;
  return format.format(value);
}
