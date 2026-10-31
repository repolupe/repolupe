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

/// E.g. `42s` or `3m 05s`.
String formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) {
    return t.base.chat.assistantMessage.durationSeconds(seconds: seconds);
  }
  return t.base.chat.assistantMessage.durationMinutes(minutes: seconds ~/ 60, seconds: (seconds % 60).toString().padLeft(2, '0'));
}

/// E.g. `12,345`.
String formatCount(int count) => NumberFormat.decimalPattern().format(count);

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
