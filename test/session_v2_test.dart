import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pine_gomoku/domain/profile.dart';
import 'package:pine_gomoku/session.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

class QueuedPair {
  final toHost = <Map<String, dynamic>>[];
  final toGuest = <Map<String, dynamic>>[];
  late final GameSession h = GameSession(
    host: true,
    profile: const Profile(),
    send: (m) async {
      toGuest.add(m);
    },
  );
  late final GameSession g = GameSession(
    host: false,
    profile: const Profile(),
    send: (m) async {
      toHost.add(m);
    },
  );
  Future<void> drain() async {
    while (toHost.isNotEmpty || toGuest.isNotEmpty) {
      if (toHost.isNotEmpty) await h.receive(toHost.removeAt(0));
      if (toGuest.isNotEmpty) await g.receive(toGuest.removeAt(0));
    }
  }

  void dispose() {
    h.dispose();
    g.dispose();
  }
}

Future<(GameSession, GameSession)> pair() async {
  late GameSession h, g;
  h = GameSession(
    host: true,
    profile: const Profile(name: 'H'),
    send: (m) async {
      scheduleMicrotask(() => g.receive(m));
    },
  );
  g = GameSession(
    host: false,
    profile: const Profile(name: 'G'),
    send: (m) async {
      scheduleMicrotask(() => h.receive(m));
    },
  );
  addTearDown(() {
    h.dispose();
    g.dispose();
  });
  await g.hello();
  await settle();
  return (h, g);
}

void main() {
  test('replayed resignation event cannot score twice', () async {
    final p = QueuedPair();
    addTearDown(p.dispose);
    await p.g.hello();
    await p.drain();
    await p.h.resign();
    final event = p.toGuest.single;
    await p.drain();
    await p.g.receive(event);
    await p.drain();
    expect(p.g.room.guestScore, 1);
    expect(p.h.room.guestScore, 1);
    expect(p.g.error, isNull);
  });
  test(
    'simultaneous rematch requests settle to one proposal and one new round',
    () async {
      final p = QueuedPair();
      addTearDown(p.dispose);
      await p.g.hello();
      await p.drain();
      await p.h.resign();
      await p.drain();
      await p.g.request('rematch');
      await p.h.request('rematch');
      await p.drain();
      expect(p.h.room.proposal?.byHost, true);
      expect(p.g.room.proposal?.byHost, true);
      expect(p.h.pending, false);
      expect(p.g.pending, false);
      await p.g.respond(true);
      await p.drain();
      expect(p.h.room.roundNumber, 2);
      expect(p.g.room.roundNumber, 2);
      expect(p.h.room.guestScore, 1);
    },
  );
  testWidgets(
    'unanswered proposal expires on both peers without granting consent',
    (tester) async {
      final p = QueuedPair();
      await p.g.hello();
      await p.drain();
      final white = p.h.myStone == 2 ? p.h : p.g;
      final original = p.h.room.hostBlack;
      await white.request('swap');
      await p.drain();
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(seconds: 5));
        await p.drain();
      }
      expect(p.h.room.proposal, isNull);
      expect(p.g.room.proposal, isNull);
      expect(p.h.room.hostBlack, original);
      expect(p.g.room.hostBlack, original);
      expect(p.h.error, isNull);
      expect(p.g.error, isNull);
      p.dispose();
    },
  );
  testWidgets(
    'missing event ack freezes host instead of permitting a second operation',
    (tester) async {
      final p = QueuedPair();
      await p.g.hello();
      await p.drain();
      await p.h.resign();
      await tester.pump(const Duration(seconds: 31));
      expect(p.h.error, isNotNull);
      await p.h.request('rematch');
      expect(p.h.room.roundNumber, 1);
      expect(p.h.room.proposal, isNull);
      p.dispose();
    },
  );
  test('random colors agree; swap consent updates both identities', () async {
    final (h, g) = await pair();
    expect(h.myStone + g.myStone, 3);
    final white = h.myStone == 2 ? h : g;
    final black = h.myStone == 1 ? h : g;
    await white.request('swap');
    await settle();
    expect(h.canPlay, false);
    expect(g.canPlay, false);
    await white.respond(true);
    await settle();
    expect(white.myStone, 2);
    await black.respond(true);
    await settle();
    expect(white.myStone, 1);
    expect(black.myStone, 2);
    expect(h.room.hostBlack, g.room.hostBlack);
  });
  test('undo, resignation and accepted rematch stay synchronized', () async {
    final (h, g) = await pair();
    final black = h.myStone == 1 ? h : g;
    final white = h.myStone == 2 ? h : g;
    await black.place(7, 7);
    await settle();
    await white.place(8, 7);
    await settle();
    await black.request('undo');
    await settle();
    await white.respond(true);
    await settle();
    expect(h.game.moves, isEmpty);
    expect(g.game.moves, isEmpty);
    await g.resign();
    await settle();
    expect(h.room.hostScore, 1);
    expect(g.room.hostScore, 1);
    await h.request('rematch');
    await settle();
    await g.respond(true);
    await settle();
    expect(h.room.roundNumber, 2);
    expect(g.room.roundNumber, 2);
    expect(h.game.finished, false);
    expect(g.game.finished, false);
    expect(h.room.hostScore, 1);
    expect(g.room.hostScore, 1);
    expect(h.myStone + g.myStone, 3);
    await h.resign();
    await settle();
    expect(h.room.guestScore, 1);
    expect(g.room.guestScore, 1);
  });
  test(
    'duplicate event cannot repeat score; stale commands cannot alter new round',
    () async {
      final (h, g) = await pair();
      await g.resign();
      await settle();
      await h.receive({
        'v': 2,
        'type': 'command',
        'round': h.round,
        'rev': 0,
        'action': 'resign',
        'data': <String, dynamic>{},
      });
      await settle();
      expect(h.room.hostScore, 1);
      expect(g.room.hostScore, 1);
      expect(h.error, isNull);
      expect(g.error, isNull);
    },
  );
  test('old version is rejected before pairing', () async {
    final h = GameSession(
      host: true,
      profile: const Profile(),
      send: (_) async {},
    );
    addTearDown(h.dispose);
    await h.receive({
      'v': 1,
      'type': 'hello',
      'profile': const Profile().toJson(),
    });
    expect(h.ready, false);
    expect(h.error, isNotNull);
  });

  test('draw consent synchronizes a half point without a winner', () async {
    final (h, g) = await pair();
    final white = h.myStone == 2 ? h : g;
    final black = h.myStone == 1 ? h : g;
    await black.place(7, 7);
    await settle();
    await white.request('draw');
    await settle();
    expect(h.game.finished, false);
    await black.respond(true);
    await settle();
    expect(h.game.finished, true);
    expect(g.game.finished, true);
    expect(h.game.winner, 0);
    expect(h.room.hostScore, .5);
    expect(g.room.guestScore, .5);
  });
}
