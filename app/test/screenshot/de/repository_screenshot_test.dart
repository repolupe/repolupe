import 'package:app/gen/strings.g.dart';
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
  initScreenshotTest(locale: AppLocale.de);

  screenshotGroup(
    description: 'Repository',
    title: 'Dein Wissen,\nauf jedem Git-Server',
    routes: {
      ...baseRoutes(germanTexts),
      '/api/v1/repositories/$documentsId': documents(germanTexts),
      '/api/v1/repositories/$documentsId/documents': {
        'documents': [
          fakeDocument(path: 'Finanzen/Gehaltsabrechnungen/2026-09.pdf'),
          fakeDocument(path: 'Versicherungen/Kfz-Police.pdf'),
          fakeDocument(path: 'Steuern/Bescheid-2023.pdf', ocr: true),
          fakeDocument(path: 'Steuern/Bescheid-2024.pdf'),
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
    ready: find.text(germanTexts.documents),
    goldenFileName: '5_repository',
  );
}
