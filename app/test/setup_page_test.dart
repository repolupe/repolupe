import 'package:app/gen/strings.g.dart';
import 'package:app/pages/setup_page.dart';
import 'package:app/service/persistence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';

import 'support/persistence.dart';

void main() {
  testWidgets('the setup page chooses between a server and this device', (tester) async {
    final persistence = (await tester.runAsync(mockPersistence))!;
    await tester.pumpWidget(
      RefenaScope(
        overrides: [persistenceProvider.overrideWithValue(persistence)],
        child: TranslationProvider(child: const MaterialApp(home: SetupPage())),
      ),
    );

    expect(find.byKey(const ValueKey('setup.kind.remote')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.kind.local')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.apiUrl')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('setup.kind.remote')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setup.apiUrl')), findsOneWidget);
    expect(find.text('Log in to your Repolupe server.'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.kind.local')), findsNothing);

    // Back returns to the choice, also on the first start, where there is no route to pop.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setup.kind.local')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup.apiUrl')), findsNothing);
  });
}
