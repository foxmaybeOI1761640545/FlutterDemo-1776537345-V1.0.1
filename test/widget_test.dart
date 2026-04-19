import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:flutter_demo/main.dart";

void main() {
  const String englishText = "Hello World";
  const String chineseText = "\u4f60\u597d \u4e16\u754c";
  const String buttonText = "\u70b9\u51fb\u5207\u6362";

  testWidgets("tap button to alternate text content", (WidgetTester tester) async {
    await tester.pumpWidget(const RainbowToggleApp());

    expect(find.text(englishText), findsNothing);
    expect(find.text(chineseText), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, buttonText));
    await tester.pump();
    expect(find.text(englishText), findsOneWidget);
    expect(find.text(chineseText), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, buttonText));
    await tester.pump();
    expect(find.text(englishText), findsNothing);
    expect(find.text(chineseText), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, buttonText));
    await tester.pump();
    expect(find.text(englishText), findsOneWidget);
    expect(find.text(chineseText), findsNothing);
  });
}
