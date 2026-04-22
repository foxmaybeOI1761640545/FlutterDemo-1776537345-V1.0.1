import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:flutter_demo/src/app.dart";
import "package:flutter_demo/src/metronome_engine.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MetronomeEngine.disablePlatformAudio = true;
  });

  tearDown(() {
    MetronomeEngine.disablePlatformAudio = false;
  });

  testWidgets("loads metronome shell and navigation tabs", (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const PulseBeatApp());
    await tester.pump();
    for (int i = 0; i < 40; i++) {
      if (find.byType(NavigationBar).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
