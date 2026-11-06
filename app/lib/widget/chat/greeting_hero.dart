import 'package:app/gen/strings.g.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The logo and a greeting, on a new chat: by the time of day with the user's first name, if they gave one, else it asks
/// what they would like to know. It fades in once the user is loaded, and is replaced by a note while the chat is
/// [temporary]. The [action] is shown below it.
class GreetingHero extends StatelessWidget {
  final bool temporary;

  /// E.g. the button to add an LLM provider while there is no model.
  final Widget? action;

  const GreetingHero({super.key, required this.temporary, this.action});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final texts = t.base.chat.startPage;
    final user = context.watch(meProvider);
    final firstName = user?.firstName;
    final greeting = firstName == null
        ? texts.greeting
        : switch (DayTime.of(DateTime.now())) {
            DayTime.night => texts.greetingNight(name: firstName),
            DayTime.morning => texts.greetingMorning(name: firstName),
            DayTime.day => texts.greetingDay(name: firstName),
            DayTime.evening => texts.greetingEvening(name: firstName),
          };
    final style = Theme.of(context).textTheme.headlineMedium;
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 80),
            const SizedBox(height: 16),
            // The lines take the same place, so the logo does not jump when a long greeting is replaced.
            Stack(
              alignment: Alignment.center,
              children: [
                _HeroLine(
                  visible: !temporary,
                  hiddenOffset: const Offset(0, -_slideOffset),
                  child: AnimatedOpacity(
                    opacity: user == null ? 0 : 1,
                    duration: _loadFadeDuration,
                    child: Text(greeting, style: style, textAlign: TextAlign.center),
                  ),
                ),
                _HeroLine(
                  visible: temporary,
                  hiddenOffset: const Offset(0, _slideOffset),
                  child: Text(t.base.chat.temporary, style: style, textAlign: TextAlign.center),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// The part of the day the greeting depends on.
enum DayTime {
  night,
  morning,
  day,
  evening;

  /// In [time]'s time zone: the morning from 5:00, the day from 12:00, the evening from 18:00, the night from 22:00.
  static DayTime of(DateTime time) => switch (time.hour) {
    < 5 || >= 22 => night,
    < 12 => morning,
    < 18 => day,
    _ => evening,
  };
}

const _loadFadeDuration = Duration(milliseconds: 250);
const _switchDuration = Duration(milliseconds: 400);

/// Of the line's height, about 12 pixels.
const _slideOffset = 0.3;

/// Toggling temporary fades the shown line out while it moves away in the first half, then the other one in:
/// the temporary line comes from below, the greeting from above.
class _HeroLine extends StatelessWidget {
  final bool visible;
  final Offset hiddenOffset;
  final Widget child;

  const _HeroLine({required this.visible, required this.hiddenOffset, required this.child});

  @override
  Widget build(BuildContext context) {
    final curve = visible ? const Interval(0.5, 1, curve: Curves.easeOut) : const Interval(0, 0.5, curve: Curves.easeIn);
    return ExcludeSemantics(
      excluding: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : hiddenOffset,
        duration: _switchDuration,
        curve: curve,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: _switchDuration,
          curve: curve,
          child: child,
        ),
      ),
    );
  }
}
