import 'game.dart';

class Proposal {
  final String kind;
  final bool byHost;
  const Proposal(this.kind, this.byHost);
}

/// Deterministic room rules, replayed on both phones in host-assigned order.
class Room {
  Game game = Game();
  bool hostBlack;
  int roundNumber = 1;
  double hostScore = 0, guestScore = 0;
  bool resigned = false;
  bool _openingClosed = false;
  Proposal? proposal;
  Room({required this.hostBlack});

  int stoneFor(bool host) => host == hostBlack ? 1 : 2;

  bool canRequest(String kind, bool actor) {
    if (proposal != null) return false;
    return switch (kind) {
      'undo' => !game.finished && _undoIndex(actor) >= 0,
      'swap' => !game.finished && !_openingClosed && stoneFor(actor) == 2,
      'rematch' => game.finished,
      _ => false,
    };
  }

  int _undoIndex(bool actor) {
    for (var i = game.moves.length - 1; i >= 0; i--) {
      if (i % 2 + 1 == stoneFor(actor)) return i;
    }
    return -1;
  }

  bool apply(String action, bool actor, Map<String, dynamic> data) {
    switch (action) {
      case 'request':
        final kind = data['kind'];
        if (kind is! String || !canRequest(kind, actor)) return false;
        proposal = Proposal(kind, actor);
        return true;
      case 'respond':
        final p = proposal;
        if (p == null || p.byHost == actor || data['accept'] is! bool) {
          return false;
        }
        if (data['accept'] == true) {
          switch (p.kind) {
            case 'undo':
              game = Game.fromMoves(
                game.toJson().take(_undoIndex(p.byHost)).toList(),
              );
            case 'swap':
              hostBlack = !hostBlack;
            case 'rematch':
              if (data['hostBlack'] is! bool) return false;
              hostBlack = data['hostBlack'];
              game = Game();
              resigned = false;
              _openingClosed = false;
              roundNumber++;
          }
        }
        proposal = null;
        return true;
      case 'move':
        if (proposal != null || game.finished || game.turn != stoneFor(actor)) {
          return false;
        }
        final x = data['x'], y = data['y'];
        if (x is! int ||
            y is! int ||
            x < 0 ||
            y < 0 ||
            x >= Game.size ||
            y >= Game.size ||
            game.at(x, y) != 0) {
          return false;
        }
        game.place(x, y, stoneFor(actor));
        _openingClosed = true;
        if (game.finished) _score();
        return true;
      case 'resign':
        if (game.finished || proposal != null) return false;
        game.winner = 3 - stoneFor(actor);
        resigned = true;
        _score();
        return true;
      default:
        return false;
    }
  }

  void _score() {
    if (game.winner == 0) {
      hostScore += .5;
      guestScore += .5;
    } else if (game.winner == stoneFor(true)) {
      hostScore++;
    } else {
      guestScore++;
    }
  }
}
