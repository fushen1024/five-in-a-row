import 'package:flutter_test/flutter_test.dart';
import 'package:pine_gomoku/domain/game.dart';

void main() {
  test('full legal board without five is a draw', () {
    final g = Game();
    final black = <(int, int)>[], white = <(int, int)>[];
    for (var y = 0; y < 15; y++) {
      for (var x = 0; x < 15; x++) {
        ((x + 2 * y) % 4 < 2 ? black : white).add((x, y));
      }
    }
    for (var i = 0; i < black.length; i++) {
      g.place(black[i].$1, black[i].$2, 1);
      if (i < white.length) g.place(white[i].$1, white[i].$2, 2);
    }
    expect(g.moves.length, 225);
    expect(g.finished, true);
    expect(g.winner, 0);
  });
  test('black starts; rejects wrong turn, outside board, occupied cell', () {
    final g = Game();
    expect(() => g.place(0, 0, 2), throwsStateError);
    expect(() => g.place(-1, 0, 1), throwsStateError);
    expect(() => g.place(15, 0, 1), throwsStateError);
    g.place(7, 7, 1);
    expect(g.turn, 2);
    expect(() => g.place(7, 7, 2), throwsStateError);
    expect(g.moves.length, 1);
  });
  for (final d in [(1, 0), (0, 1), (1, 1), (1, -1)]) {
    test('five wins in direction $d; finished game rejects moves', () {
      final g = Game();
      for (var i = 0; i < 5; i++) {
        g.place(3 + i * d.$1, 8 + i * d.$2, 1);
        if (i < 4) g.place(i * 2, 0, 2);
      }
      expect(g.winner, 1);
      expect(g.winningCells.length, 5);
      expect(() => g.place(14, 14, 2), throwsStateError);
      expect(Game.fromMoves(g.toJson()).winner, 1);
    });
  }
  test('snapshot replay rejects malformed and illegal history', () {
    expect(
      () => Game.fromMoves([
        [7, 7],
        [7, 7],
      ]),
      throwsStateError,
    );
    expect(
      () => Game.fromMoves([
        [7],
      ]),
      throwsFormatException,
    );
    expect(
      () => Game.fromMoves([
        ['x', 7],
      ]),
      throwsFormatException,
    );
  });
}
