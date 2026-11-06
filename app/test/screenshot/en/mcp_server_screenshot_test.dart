import 'package:app/pages/settings/mcp_server_name_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/sample_data.dart';
import '../util/screenshot_scaffold.dart';

/// Screenshot test for picking a new MCP server.
///
/// Run `flutter test test/screenshot --update-goldens`
/// to (re)generate the golden images, or `flutter test test/screenshot` to compare against them.
void main() {
  initScreenshotTest();

  screenshotGroup(
    description: 'MCP server',
    title: 'Connect any\nMCP server',
    api: sampleApi(englishTexts),
    home: const Scaffold(),
    pushed: const McpServerNamePickerPage(name: ''),
    ready: find.text('Exa'),
    goldenFileName: '5_mcp_server',
  );
}
