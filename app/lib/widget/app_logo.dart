import 'package:app/gen/strings.g.dart';
import 'package:flutter/material.dart';

/// The logo, white in the dark theme.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? 'assets/logo-512-white.webp' : 'assets/logo-512.webp',
      width: size,
      height: size,
      semanticLabel: context.t.base.app.logoAlt,
    );
  }
}
