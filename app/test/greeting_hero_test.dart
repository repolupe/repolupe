import 'package:app/widget/chat/greeting_hero.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each part of the day starts on the hour', () {
    DayTime at(int hour, [int minute = 0]) => DayTime.of(DateTime(2026, 11, 6, hour, minute));

    expect(at(4, 59), DayTime.night);
    expect(at(5), DayTime.morning);
    expect(at(11, 59), DayTime.morning);
    expect(at(12), DayTime.day);
    expect(at(17, 59), DayTime.day);
    expect(at(18), DayTime.evening);
    expect(at(21, 59), DayTime.evening);
    expect(at(22), DayTime.night);
    expect(at(0), DayTime.night);
  });
}
