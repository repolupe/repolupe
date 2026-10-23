import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _deploymentTarget(input),
    ).run(input: input, output: output);
  });
}

/// The minimum OS version Flutter builds for. Without it rustc links for its
/// own default (iOS 10.0) while cc compiles the C dependencies for the SDK's
/// version, so symbols missing before iOS 13 (`___chkstk_darwin`) don't link.
Map<String, String> _deploymentTarget(BuildInput input) {
  if (!input.config.buildCodeAssets) return const {};
  final code = input.config.code;
  return switch (code.targetOS) {
    OS.iOS => {'IPHONEOS_DEPLOYMENT_TARGET': '${code.iOS.targetVersion}.0'},
    OS.macOS => {'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}.0'},
    _ => const {},
  };
}
