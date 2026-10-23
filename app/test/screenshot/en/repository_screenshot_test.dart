import 'package:app/pages/settings/repository_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../support/fake_repository.dart';
import '../util/sample_data.dart';
import '../util/screenshot_scaffold.dart';

/// Screenshot test for a repository's page.
///
/// Run `flutter test test/screenshot --update-goldens`
/// to (re)generate the golden images, or `flutter test test/screenshot` to compare against them.
void main() {
  initScreenshotTest();

  screenshotGroup(
    description: 'Repository',
    title: 'Your knowledge,\non any git server',
    routes: {
      ...baseRoutes(),
      '/api/v1/repositories/$documentsId': documents,
      '/api/v1/repositories/$documentsId/documents': {
        'documents': [
          fakeDocument(path: 'Finance/Payslips/2026-09.pdf'),
          fakeDocument(path: 'Insurance/Car-Policy.pdf'),
          fakeDocument(path: 'Taxes/Assessment-2023.pdf', ocr: true),
          fakeDocument(path: 'Taxes/Assessment-2024.pdf'),
        ],
        'paused_until': null,
      },
      '/api/v1/repositories/$documentsId/users': [
        fakeRepositoryUser(userId: '0199a8d4-6d5e-7c3a-9b1f-400000000001', userName: 'sam', email: 'sam@example.com', canCommit: true),
        fakeRepositoryUser(userId: '0199a8d4-6d5e-7c3a-9b1f-400000000002', userName: 'robin', email: 'robin@example.com'),
      ],
    },
    home: const Scaffold(),
    pushed: RepositoryPage(id: UuidValue.fromString(documentsId)),
    ready: find.text('documents'),
    goldenFileName: '4_repository',
  );
}
