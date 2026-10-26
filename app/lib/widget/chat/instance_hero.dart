import 'package:app/gen/strings.g.dart';
import 'package:app/service/instance_name_provider.dart';
import 'package:app/widget/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The logo and the server's name, on a new chat. The name fades in once loaded, and is replaced by
/// a note while the chat is [temporary].
class InstanceHero extends StatelessWidget {
  final bool temporary;

  const InstanceHero({super.key, required this.temporary});

  @override
  Widget build(BuildContext context) {
    final instanceName = context.watch(instanceNameProvider).data;
    final style = Theme.of(context).textTheme.headlineMedium;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 80),
            const SizedBox(height: 16),
            // The lines take the same place, so the logo does not jump when a long name is replaced.
            Stack(
              alignment: Alignment.center,
              children: [
                _HeroLine(
                  visible: !temporary,
                  hiddenOffset: const Offset(0, -_slideOffset),
                  child: AnimatedOpacity(
                    opacity: instanceName == null ? 0 : 1,
                    duration: _loadFadeDuration,
                    child: Text(instanceName ?? productName, style: style, textAlign: TextAlign.center),
                  ),
                ),
                _HeroLine(
                  visible: temporary,
                  hiddenOffset: const Offset(0, _slideOffset),
                  child: Text(context.t.base.chat.temporary, style: style, textAlign: TextAlign.center),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _loadFadeDuration = Duration(milliseconds: 250);
const _switchDuration = Duration(milliseconds: 400);

/// Of the line's height, about 12 pixels.
const _slideOffset = 0.3;

/// Toggling temporary fades the shown line out while it moves away in the first half, then the other one in:
/// the temporary line comes from below, the name from above.
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
