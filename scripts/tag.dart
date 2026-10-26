import 'dart:io';

/// Tags the current commit with the app's version from `app/pubspec.yaml`, without the build number: `1.0.1+3`
/// becomes `v1.0.1`.
///
/// Run from the repository root: `dart scripts/tag.dart`.
void main() {
  final root = File.fromUri(Platform.script).parent.parent;
  final pubspec = File('${root.path}/app/pubspec.yaml').readAsStringSync();
  final match = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec);
  if (match == null) {
    throw const FormatException('app/pubspec.yaml: no version found');
  }
  final tag = 'v${match.group(1)}';
  final result = Process.runSync('git', ['tag', '-a', tag, '-m', 'Release $tag'], workingDirectory: root.path);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }
  // ignore: avoid_print
  print('Tagged $tag');
}
