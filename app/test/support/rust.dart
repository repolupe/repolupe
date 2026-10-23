import 'dart:io';

import 'package:app/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Loads the Rust library for a test file.
///
/// `flutter test` runs the build hook but does not bundle the library, and
/// the generated loader only finds it in a bundle, so open the hook's output
/// (https://github.com/fzyzcjy/flutter_rust_bridge/issues/3379).
Future<void> initRustLib() async {
  final os = Platform.operatingSystem;
  final library = switch (os) {
    'macos' => 'build/native_assets/macos/librepolupe_ffi.dylib',
    'linux' => 'build/native_assets/linux/librepolupe_ffi.so',
    'windows' => 'build/native_assets/windows/repolupe_ffi.dll',
    _ => throw UnsupportedError('No test library path for $os'),
  };
  await RustLib.init(externalLibrary: ExternalLibrary.open(library));
}
