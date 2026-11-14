import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// The compressor, encoding every file as the [result] (none if it fails), or throwing if [fails] is set.
class FakeImageCompress extends FlutterImageCompressPlatform {
  final Uint8List? result;
  final bool fails;

  /// The paths of the files it was asked to compress.
  final paths = <String>[];

  /// What the last file was asked for with.
  ({int minWidth, int minHeight, int quality, CompressFormat format})? options;

  FakeImageCompress({this.result, this.fails = false});

  @override
  Future<Uint8List?> compressWithFile(
    String path, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) async {
    paths.add(path);
    options = (minWidth: minWidth, minHeight: minHeight, quality: quality, format: format);
    if (fails) {
      throw UnsupportedError('No WebP encoder');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
