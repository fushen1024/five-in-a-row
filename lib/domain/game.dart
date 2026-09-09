class Game {
  static const size = 15;
  final List<int> _board = List.filled(size * size, 0);
  final List<(int, int)> _moves = [];
  List<(int, int)> get moves => List.unmodifiable(_moves);
  List<(int, int)> winningCells = [];
  int winner = 0;
  bool draw = false;
  int get turn => _moves.length.isEven ? 1 : 2;
  bool get finished => winner != 0 || draw || _moves.length == size * size;
  int at(int x, int y) => _board[y * size + x];

  void finishDraw() {
    if (!finished) draw = true;
  }

  void place(int x, int y, int stone) {
    if (finished ||
        stone != turn ||
        x < 0 ||
        y < 0 ||
        x >= size ||
        y >= size ||
        at(x, y) != 0) {
      throw StateError('无效落子');
    }
    _board[y * size + x] = stone;
    _moves.add((x, y));
    for (final (dx, dy) in [(1, 0), (0, 1), (1, 1), (1, -1)]) {
      final line = <(int, int)>[(x, y)];
      for (final sign in [-1, 1]) {
        var nx = x + dx * sign, ny = y + dy * sign;
        while (nx >= 0 &&
            ny >= 0 &&
            nx < size &&
            ny < size &&
            at(nx, ny) == stone) {
          if (sign == -1) {
            line.insert(0, (nx, ny));
          } else {
            line.add((nx, ny));
          }
          nx += dx * sign;
          ny += dy * sign;
        }
      }
      if (line.length >= 5) {
        winner = stone;
        winningCells = line;
        break;
      }
    }
  }

  List<List<int>> toJson() => _moves.map((m) => [m.$1, m.$2]).toList();
  static Game fromMoves(dynamic data) {
    if (data is! List || data.length > size * size) {
      throw const FormatException('无效棋谱');
    }
    final game = Game();
    for (final move in data) {
      if (move is! List ||
          move.length != 2 ||
          move[0] is! int ||
          move[1] is! int) {
        throw const FormatException('无效坐标');
      }
      game.place(move[0], move[1], game.turn);
    }
    return game;
  }
}
