import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:flutter_demo/src/app.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("loads metronome shell and navigation tabs", (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(const PulseBeatApp());
    await tester.pumpAndSettle();

    expect(find.text("节拍器"), findsAtLeastNWidgets(1));
    expect(find.text("预设"), findsAtLeastNWidgets(1));
    expect(find.text("设置"), findsAtLeastNWidgets(1));

    await tester.tap(find.text("预设").last);
    await tester.pumpAndSettle();
    expect(find.text("预设管理"), findsOneWidget);

    await tester.tap(find.text("设置").last);
    await tester.pumpAndSettle();
    expect(find.text("界面与数据"), findsOneWidget);
  });
}
