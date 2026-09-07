import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pine_gomoku/main.dart';

void main() {
  testWidgets('phone UI fits and renders lobby and played board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
    if (emoji.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync())));
      await loader.load();
    }
    SharedPreferences.setMockInitialValues({});
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const PineApp(autoScan: false)),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs/screenshots').create(recursive: true);
        await File(
          'docs/screenshots/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('lobby');
    await tester.ensureVisible(find.text('同机练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同机练习'));
    await tester.pumpAndSettle();
    for (final p in [(8, 8), (9, 8), (7, 9), (9, 7), (6, 10), (9, 9)]) {
      await tester.tap(find.bySemanticsLabel('第${p.$1}列第${p.$2}行，空位'));
      await tester.pumpAndSettle();
    }
    await capture('match');
    expect(tester.takeException(), isNull);
  });
}
