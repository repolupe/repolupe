import 'package:app/gen/strings.g.dart';
import 'package:app/pages/settings/admin/llm_provider_name_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/sample_data.dart';
import '../util/screenshot_scaffold.dart';

/// Screenshot test for picking a new LLM provider.
///
/// Run `flutter test test/screenshot --update-goldens`
/// to (re)generate the golden images, or `flutter test test/screenshot` to compare against them.
void main() {
  initScreenshotTest(locale: AppLocale.de);

  screenshotGroup(
    description: 'LLM provider',
    title: 'Der LLM-Anbieter\ndeiner Wahl',
    api: sampleApi(germanTexts),
    home: const Scaffold(),
    pushed: const LlmProviderNamePickerPage(name: ''),
    ready: find.text('Anthropic'),
    goldenFileName: '3_llm_provider',
  );
}
