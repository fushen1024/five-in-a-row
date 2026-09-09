import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pine_gomoku/main.dart';
import 'package:pine_gomoku/domain/profile.dart';
import 'package:pine_gomoku/ui/board.dart';
import 'package:pine_gomoku/session.dart';

void main() {
  testWidgets(
    'incoming network proposal blocks play and only receiver can answer',
    (tester) async {
      final session = GameSession(
        host: true,
        profile: const Profile(name: '松客'),
        send: (_) async {},
      );
      session.ready = true;
      session.room.hostBlack = true;
      session.room.apply('request', false, {'kind': 'swap'});
      await tester.pumpWidget(
        MaterialApp(
          home: MatchPage(
            profile: session.profile,
            local: false,
            initialSession: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Board>(find.byType(Board)).enabled, isFalse);
      expect(find.text('对方申请换色'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '同意'))
            .onPressed,
        isNotNull,
      );
      session.pending = true;
      session.changed();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '同意'))
            .onPressed,
        isNull,
      );
      session.pending = false;
      session.room.apply('respond', true, {'accept': false});
      session.room.hostBlack = false;
      session.room.apply('request', true, {'kind': 'swap'});
      session.changed();
      await tester.pump();
      expect(find.text('已申请换色，等待对方同意'), findsOneWidget);
      expect(find.text('同意'), findsNothing);
      session.fail('测试断线');
      await tester.pump();
      expect(tester.widget<Board>(find.byType(Board)).enabled, isFalse);
      for (final button in tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      )) {
        expect(button.onPressed, isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MatchPage(profile: Profile(name: '松客'), local: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shared device exchange requires consent and ends after first move',
    (tester) async {
      await open(tester);
      expect(find.text('第 1 局'), findsOneWidget);
      await tap(tester, '申请换色');
      expect(find.text('请将设备交给对方确认。双方同意后交换黑白。'), findsOneWidget);
      await tap(tester, '同意');
      tester.widget<Board>(find.byType(Board)).onPlace(7, 7);
      await tester.pumpAndSettle();
      final swap = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '申请换色'),
      );
      expect(swap.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared device undo rejects then accepts without changing score',
    (tester) async {
      await open(tester);
      final board = tester.widget<Board>(find.byType(Board));
      board.onPlace(7, 7);
      await tester.pumpAndSettle();
      await tap(tester, '申请悔棋');
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '白方申请'))
            .onPressed,
        isNull,
      );
      await tap(tester, '黑方申请');
      await tap(tester, '拒绝');
      expect(tester.widget<Board>(find.byType(Board)).game.moves.length, 1);
      await tap(tester, '申请悔棋');
      await tap(tester, '黑方申请');
      await tap(tester, '同意');
      expect(tester.widget<Board>(find.byType(Board)).game.moves, isEmpty);
      expect(find.text('0 分'), findsNWidgets(2));
    },
  );

  for (final requester in ['黑方申请', '白方申请']) {
    testWidgets(
      'shared device undo chooses $requester and rolls back its last move',
      (tester) async {
        await open(tester);
        tester.widget<Board>(find.byType(Board)).onPlace(7, 7);
        await tester.pumpAndSettle();
        tester.widget<Board>(find.byType(Board)).onPlace(8, 7);
        await tester.pumpAndSettle();
        await tap(tester, '申请悔棋');
        await tap(tester, requester);
        expect(tester.widget<Board>(find.byType(Board)).game.moves.length, 2);
        await tap(tester, '同意');
        final game = tester.widget<Board>(find.byType(Board)).game;
        expect(game.moves.length, requester == '黑方申请' ? 0 : 1);
        expect(game.at(8, 7), 0);
        expect(game.at(7, 7), requester == '黑方申请' ? 0 : 1);
      },
    );
  }

  testWidgets('resign confirms and rematch preserves identity scores', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, '认输');
    await tap(tester, '继续下棋');
    expect(tester.widget<Board>(find.byType(Board)).game.finished, isFalse);
    await tap(tester, '认输');
    await tap(tester, '确认认输');
    expect(tester.widget<Board>(find.byType(Board)).game.finished, isTrue);
    expect(find.text('1 分'), findsOneWidget);
    await tap(tester, '再来一局');
    await tap(tester, '同意');
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(find.text('第 2 局'), findsOneWidget);
    expect(find.text('1 分'), findsOneWidget);
    expect(tester.widget<Board>(find.byType(Board)).game.finished, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('draw can be rejected then agreed and rematched', (tester) async {
    await open(tester);
    await tap(tester, '申请和棋');
    expect(find.textContaining('双方各得 0.5 分'), findsOneWidget);
    await tap(tester, '拒绝');
    expect(tester.widget<Board>(find.byType(Board)).game.finished, false);
    await tap(tester, '申请和棋');
    await tap(tester, '同意');
    expect(tester.widget<Board>(find.byType(Board)).game.finished, true);
    expect(tester.widget<Board>(find.byType(Board)).game.winner, 0);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(find.text('0.5 分'), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('再来一局'), 200);
    await tap(tester, '再来一局');
    await tap(tester, '同意');
    expect(tester.widget<Board>(find.byType(Board)).game.finished, false);
  });
}
