import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Records what it is asked to save, failing if [error] is set.
class FakeFilePicker extends FilePickerPlatform {
  final PlatformException? error;
  final saved = <(String, Uint8List, String)>[];

  FakeFilePicker({this.error});

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (error case final error?) {
      throw error;
    }
    saved.add((fileName, bytes, mimeType));
    return Uri.file('/saved/$fileName');
  }
}
