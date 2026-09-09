import 'package:flutter_test/flutter_test.dart';
import 'package:pine_gomoku/domain/room.dart';

void main() {
  test('draw awards half point each and rematch does not award again', () {
    final r = Room(hostBlack: true);
    final black = <(int, int)>[], white = <(int, int)>[];
    for (var y = 0; y < 15; y++) {
      for (var x = 0; x < 15; x++) {
        ((x + 2 * y) % 4 < 2 ? black : white).add((x, y));
      }
    }
    for (var i = 0; i < black.length; i++) {
      r.apply('move', true, {'x': black[i].$1, 'y': black[i].$2});
      if (i < white.length) {
        r.apply('move', false, {'x': white[i].$1, 'y': white[i].$2});
      }
    }
    expect(r.game.finished, true);
    expect(r.game.winner, 0);
    expect(r.hostScore, .5);
    expect(r.guestScore, .5);
    r.apply('request', false, {'kind': 'rematch'});
    r.apply('respond', true, {'accept': true, 'hostBlack': false});
    expect(r.hostScore, .5);
    expect(r.guestScore, .5);
  });
  test(
    'undo needs peer consent and restores requester turn including reply',
    () {
      final r = Room(hostBlack: true);
      r.apply('move', true, {'x': 7, 'y': 7});
      r.apply('move', false, {'x': 8, 'y': 7});
      expect(r.apply('request', true, {'kind': 'undo'}), true);
      expect(r.apply('move', true, {'x': 9, 'y': 7}), false);
      expect(r.apply('respond', true, {'accept': true}), false);
      expect(r.game.moves.length, 2);
      expect(r.apply('respond', false, {'accept': true}), true);
      expect(r.game.moves, isEmpty);
      expect(r.game.turn, 1);
      expect(r.hostScore, 0);
    },
  );
  test('undo before reply removes one move; rejection retains board', () {
    final r = Room(hostBlack: false);
    r.apply('move', false, {'x': 1, 'y': 1});
    r.apply('request', false, {'kind': 'undo'});
    r.apply('respond', true, {'accept': false});
    expect(r.game.moves.length, 1);
    expect(r.proposal, isNull);
    r.apply('request', false, {'kind': 'undo'});
    r.apply('respond', true, {'accept': true});
    expect(r.game.moves, isEmpty);
  });
  test('only white can request black before first move', () {
    final r = Room(hostBlack: true);
    expect(r.apply('request', true, {'kind': 'swap'}), false);
    expect(r.apply('request', false, {'kind': 'swap'}), true);
    r.apply('respond', true, {'accept': true});
    expect(r.stoneFor(false), 1);
    r.apply('move', false, {'x': 0, 'y': 0});
    expect(r.apply('request', true, {'kind': 'swap'}), false);
  });
  test('undoing opening does not reopen color negotiation', () {
    final r = Room(hostBlack: true);
    r.apply('move', true, {'x': 0, 'y': 0});
    r.apply('request', true, {'kind': 'undo'});
    r.apply('respond', false, {'accept': true});
    expect(r.game.moves, isEmpty);
    expect(r.canRequest('swap', false), false);
  });
  test(
    'resignation awards once; rematch keeps player scores and resets board',
    () {
      final r = Room(hostBlack: false);
      expect(r.apply('resign', false, {}), true);
      expect(r.game.winner, 2);
      expect(r.hostScore, 1);
      expect(r.apply('resign', false, {}), false);
      expect(r.apply('request', true, {'kind': 'undo'}), false);
      r.apply('request', true, {'kind': 'rematch'});
      expect(
        r.apply('respond', true, {'accept': true, 'hostBlack': true}),
        false,
      );
      r.apply('respond', false, {'accept': true, 'hostBlack': true});
      expect(r.roundNumber, 2);
      expect(r.game.finished, false);
      expect(r.hostBlack, true);
      expect(r.hostScore, 1);
      expect(r.guestScore, 0);
      expect(r.resigned, false);
    },
  );
  test('normal win awards identity even when host is white', () {
    final r = Room(hostBlack: false);
    for (var i = 0; i < 5; i++) {
      r.apply('move', false, {'x': i, 'y': 7});
      if (i < 4) r.apply('move', true, {'x': i * 2, 'y': 0});
    }
    expect(r.guestScore, 1);
    expect(r.hostScore, 0);
    expect(r.apply('move', true, {'x': 9, 'y': 0}), false);
    expect(r.guestScore, 1);
  });
  test('invalid or premature actions have no side effects', () {
    final r = Room(hostBlack: true);
    expect(r.apply('request', true, {'kind': 'undo'}), false);
    expect(r.apply('request', true, {'kind': 'rematch'}), false);
    expect(r.apply('respond', false, {'accept': true}), false);
    expect(r.apply('move', false, {'x': 0, 'y': 0}), false);
    expect(r.apply('move', true, {'x': -1, 'y': 0}), false);
    expect(r.game.moves, isEmpty);
  });
}
