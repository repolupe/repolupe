import 'package:flutter/services.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// The camera, taking the [photo] (none if the user cancels), or failing if [error] is set.
class FakeImagePicker extends ImagePickerPlatform {
  final XFile? photo;
  final PlatformException? error;

  /// What the last photo was asked for with.
  ImagePickerOptions? options;

  FakeImagePicker({this.photo, this.error});

  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) async {
    this.options = options;
    if (error case final error?) {
      throw error;
    }
    return source == ImageSource.camera ? photo : null;
  }
}
