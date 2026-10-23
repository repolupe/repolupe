import 'package:app/pages/settings/admin/llm_provider_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_llm.dart';
import '../util/sample_data.dart';
import '../util/screenshot_scaffold.dart';

/// Screenshot test for editing an LLM provider.
///
/// Run `flutter test test/screenshot --update-goldens`
/// to (re)generate the golden images, or `flutter test test/screenshot` to compare against them.
void main() {
  initScreenshotTest();

  screenshotGroup(
    description: 'LLM provider',
    title: 'The LLM provider\nof your choice',
    routes: baseRoutes(),
    home: const Scaffold(),
    pushed: LlmProviderFormPage.edit(
      provider: llmProviderOf(
        fakeLlmProvider(
          id: sampleProviderId,
          name: 'OpenRouter',
          apiFormat: 'OPENAI',
          baseUrl: 'https://openrouter.ai/api/v1',
          keyHint: 'x9Qa',
        ),
      ),
    ),
    ready: find.text('OpenRouter'),
    goldenFileName: '3_llm_provider',
  );
}
