import 'package:flutter/material.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

extension ScreenshotDeviceExt on ScreenshotDevice {
  /// This device in a [CustomFrame] with [title] above it.
  ScreenshotDevice wrapWithTitle({
    required String title,
  }) {
    final originalDevice = this;
    return ScreenshotDevice(
      platform: originalDevice.platform,
      resolution: originalDevice.resolution,
      pixelRatio: originalDevice.pixelRatio,
      goldenSubFolder: originalDevice.goldenSubFolder,
      frameBuilder:
          ({
            required ScreenshotDevice device,
            required ScreenshotFrameColors? frameColors,
            required Widget child,
          }) {
            return CustomFrame(
              title: title,
              originalBuilder: originalDevice.frameBuilder,
              device: device,
              frameColors: frameColors,
              child: child,
            );
          },
    );
  }
}

/// The marketing frame: [title] on a gradient in the colors of the logo, above the whole device with its system UI
/// (scaled down to fit, so that the message input of a chat is shown too).
class CustomFrame extends StatelessWidget {
  const CustomFrame({
    super.key,
    required this.title,
    required this.originalBuilder,
    required this.device,
    required this.frameColors,
    required this.child,
  });

  final String title;
  final ScreenshotFrameBuilder originalBuilder;
  final ScreenshotDevice device;
  final ScreenshotFrameColors? frameColors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final logicalSize = device.resolution / device.pixelRatio;
    final isTablet = logicalSize.shortestSide >= 600;
    final borderRadius = isTablet ? 24.0 : 64.0;
    final borderSize = isTablet ? 4.0 : 8.0;

    // The device is pinned this far from the top; the title fills the
    // remaining space above it so long / multi-line titles never overlap it.
    const frameTop = 210.0;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A3290), Color(0xFF00002B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              height: frameTop,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: frameTop,
              left: 8,
              right: 8,
              bottom: 24,
              child: FittedBox(
                child: Container(
                  width: device.resolution.width / device.pixelRatio,
                  height: device.resolution.height / device.pixelRatio,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(width: borderSize, color: const Color(0xFFF29A2E)),
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: originalBuilder(
                    device: device,
                    frameColors: frameColors,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
