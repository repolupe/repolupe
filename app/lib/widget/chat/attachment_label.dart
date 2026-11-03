import 'package:app/util/format.dart';
import 'package:flutter/material.dart';

/// The name of an attached file followed by its size in [sizeColor], in one line.
class AttachmentLabel extends StatelessWidget {
  final String fileName;
  final int size;
  final Color sizeColor;

  const AttachmentLabel({super.key, required this.fileName, required this.size, required this.sizeColor});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: fileName,
        children: [
          TextSpan(
            text: '  ${formatBytes(size)}',
            style: TextStyle(color: sizeColor),
          ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
