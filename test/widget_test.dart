import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pine_gomoku/main.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('lobby and board scroll correctly at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PineApp(autoScan: false));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('同机练习'), 180);
      await tester.pumpAndSettle();
      await tester.tap(find.text('同机练习'));
      await tester.pumpAndSettle();
      final center = find.bySemanticsLabel('第8列第8行，空位');
      await tester.scrollUntilVisible(center, 120);
      await tester.pumpAndSettle();
      await tester.tap(center);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('第8列第8行，黑子'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('轮到白方落子'), -120);
      await tester.pumpAndSettle();
      expect(find.text('轮到白方落子'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('lobby, offline game and profile are usable', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PineApp(autoScan: false));
    await tester.pumpAndSettle();
    expect(find.text('松间'), findsOneWidget);
    await tester.ensureVisible(find.text('同机练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同机练习'));
    await tester.pumpAndSettle();
    expect(find.text('黑方先行'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('第8列第8行，空位'));
    await tester.pumpAndSettle();
    expect(find.text('轮到白方落子'), findsOneWidget);
    await tester.tap(find.byTooltip('返回大厅'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('离开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '云间棋友');
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.text('云间棋友'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
