import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pine_gomoku/domain/profile.dart';
import 'package:pine_gomoku/session.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
void main() {
  test('an unsolicited acknowledgment cannot start a game', () async {
    final host = GameSession(
      host: true,
      profile: const Profile(),
      send: (_) async {},
    );
    await host.receive({'v': 1, 'type': 'ack', 'round': ''});
    expect(host.ready, false);
    expect(host.canPlay, false);
    host.dispose();
  });
  test('first snapshot must describe an empty opening board', () async {
    final guest = GameSession(
      host: false,
      profile: const Profile(),
      send: (_) async {},
    );
    await guest.receive({
      'v': 1,
      'type': 'state',
      'round': 'foreign',
      'moves': [
        [7, 7],
      ],
      'profile': const Profile().toJson(),
    });
    expect(guest.ready, false);
    expect(guest.game.moves, isEmpty);
    guest.dispose();
  });
  testWidgets('missing handshake confirmation expires without allowing moves', (
    tester,
  ) async {
    final guest = GameSession(
      host: false,
      profile: const Profile(),
      send: (_) async {},
    );
    await guest.hello();
    await tester.pump(const Duration(seconds: 31));
    expect(guest.error, contains('未确认'));
    expect(guest.canPlay, false);
    guest.dispose();
  });
  test(
    'host and guest exchange profiles and synchronize a complete win',
    () async {
      late GameSession host, guest;
      host = GameSession(
        host: true,
        profile: const Profile(name: '房主'),
        send: (m) async {
          scheduleMicrotask(() => guest.receive(m));
        },
      );
      guest = GameSession(
        host: false,
        profile: const Profile(name: '访客'),
        send: (m) async {
          scheduleMicrotask(() => host.receive(m));
        },
      );
      await guest.hello();
      await settle();
      expect(host.ready, true);
      expect(guest.ready, true);
      expect(guest.remote?.name, '房主');
      for (var i = 0; i < 5; i++) {
        await host.place(i, 7);
        await settle();
        if (i < 4) {
          await guest.place(i * 2, 0);
          await settle();
        }
      }
      expect(host.game.winner, 1);
      expect(guest.game.toJson(), host.game.toJson());
      host.dispose();
      guest.dispose();
    },
  );
  test('illegal out-of-turn request cannot mutate host game', () async {
    final host = GameSession(
      host: true,
      profile: const Profile(),
      send: (_) async {},
    );
    await host.receive({
      'v': 1,
      'type': 'hello',
      'profile': const Profile().toJson(),
    });
    await host.receive({
      'v': 1,
      'type': 'move',
      'round': host.round,
      'seq': 0,
      'x': 7,
      'y': 7,
    });
    expect(host.game.moves, isEmpty);
    host.dispose();
  });
  test('disconnect freezes play and shows actionable message', () async {
    final host = GameSession(
      host: true,
      profile: const Profile(),
      send: (_) async {},
    );
    host.fail('连接已断开，请返回大厅重新建房');
    await host.place(7, 7);
    expect(host.game.moves, isEmpty);
    expect(host.error, contains('断开'));
    host.dispose();
  });
}
