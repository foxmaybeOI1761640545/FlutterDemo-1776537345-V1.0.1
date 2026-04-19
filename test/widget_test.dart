import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:flutter_demo/src/app.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("loads metronome shell and navigation tabs", (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const PulseBeatApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    expect(find.byIcon(Icons.library_music_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsAtLeastNWidgets(1));

    await tester.tap(find.byIcon(Icons.library_music_rounded));
    await tester.pumpAndSettle();
    expect(find.text("预设管理"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text("界面与数据"), findsOneWidget);
  });
}
