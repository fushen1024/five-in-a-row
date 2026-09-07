import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'domain/game.dart';
import 'domain/profile.dart';

typedef SendMessage = Future<void> Function(Map<String, dynamic> message);

class GameSession extends ChangeNotifier {
  final bool host;
  final Profile profile;
  final SendMessage send;
  Profile? remote;
  Game game = Game();
  String round = '';
  String? error;
  bool ready = false, pending = false;
  bool _disposed = false;
  int? _awaitingAck;
  Timer? _heartbeat, _deadline;
  DateTime _lastSeen = DateTime.now();
  Future<void> _inbox = Future.value();
  GameSession({required this.host, required this.profile, required this.send});
  int get myStone => host ? 1 : 2;
  bool get canPlay =>
      ready &&
      error == null &&
      !pending &&
      !game.finished &&
      game.turn == myStone;

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> emit(String type, [Map<String, dynamic> data = const {}]) async {
    if (_disposed || error != null) return;
    try {
      await send({'v': 1, 'type': type, ...data});
    } catch (_) {
      fail('消息发送失败，请返回大厅重新连接');
    }
  }

  void deadline() {
    _deadline?.cancel();
    _deadline = Timer(
      const Duration(seconds: 30),
      () => fail('对方未确认消息，请返回大厅重新连接'),
    );
  }

  void startHeartbeat() {
    _lastSeen = DateTime.now();
    _heartbeat ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_lastSeen).inSeconds > 25) {
        fail('连接已中断，请返回大厅重新建房');
      } else {
        unawaited(emit('ping'));
      }
    });
  }

  Future<void> hello() async {
    deadline();
    await emit('hello', {'profile': profile.toJson()});
  }

  Future<void> snapshot({bool welcome = false}) async {
    pending = true;
    _awaitingAck = game.moves.length;
    deadline();
    changed();
    await emit('state', {
      'round': round,
      'moves': game.toJson(),
      if (welcome) 'profile': profile.toJson(),
    });
  }

  Future<void> receive(Map<String, dynamic> message) {
    _inbox = _inbox.then((_) => _receive(message));
    return _inbox;
  }

  Future<void> _receive(Map<String, dynamic> m) async {
    if (_disposed || error != null) return;
    try {
      if (m['v'] != 1) throw const FormatException('游戏版本不兼容');
      _lastSeen = DateTime.now();
      switch (m['type']) {
        case 'hello':
          if (!host || remote != null) throw const FormatException('重复握手');
          remote = Profile.fromJson(m['profile']);
          round =
              '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
          await snapshot(welcome: true);
        case 'state':
          if (host || m['round'] is! String || (m['round'] as String).isEmpty) {
            throw const FormatException('无效对局状态');
          }
          if (round.isNotEmpty && m['round'] != round) {
            throw const FormatException('局号不符');
          }
          final next = Game.fromMoves(m['moves']);
          if (remote == null && next.moves.isNotEmpty) {
            throw const FormatException('开局棋盘不为空');
          }
          if (next.moves.length < game.moves.length ||
              next.moves.length > game.moves.length + 1) {
            throw const FormatException('步号不连续');
          }
          for (var i = 0; i < game.moves.length; i++) {
            if (game.moves[i] != next.moves[i]) {
              throw const FormatException('棋谱不一致');
            }
          }
          remote ??= Profile.fromJson(m['profile']);
          round = m['round'];
          game = next;
          pending = false;
          ready = true;
          _deadline?.cancel();
          startHeartbeat();
          await emit('ack', {'round': round, 'seq': game.moves.length});
        case 'ack':
          if (!host ||
              remote == null ||
              _awaitingAck == null ||
              m['round'] != round ||
              m['seq'] != _awaitingAck) {
            return;
          }
          _awaitingAck = null;
          pending = false;
          ready = true;
          _deadline?.cancel();
          startHeartbeat();
        case 'move':
          if (!host ||
              !ready ||
              pending ||
              m['round'] != round ||
              m['seq'] != game.moves.length ||
              m['x'] is! int ||
              m['y'] is! int ||
              game.turn != 2) {
            return;
          }
          game.place(m['x'], m['y'], 2);
          await snapshot();
        case 'ping':
          if (remote != null) await emit('pong');
        case 'pong':
          break;
        case 'leave':
          fail('对方已离开，请返回大厅重新建房');
        default:
          throw const FormatException('未知消息类型');
      }
      changed();
    } catch (_) {
      fail('对局数据异常或版本不兼容，请重新连接');
    }
  }

  Future<void> place(int x, int y) async {
    if (!canPlay) return;
    if (x < 0 ||
        y < 0 ||
        x >= Game.size ||
        y >= Game.size ||
        game.at(x, y) != 0) {
      return;
    }
    if (host) {
      game.place(x, y, 1);
      await snapshot();
    } else {
      pending = true;
      deadline();
      changed();
      await emit('move', {
        'round': round,
        'seq': game.moves.length,
        'x': x,
        'y': y,
      });
    }
  }

  void fail(String reason) {
    if (_disposed || error != null) return;
    error = reason;
    ready = false;
    pending = false;
    _heartbeat?.cancel();
    _deadline?.cancel();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _deadline?.cancel();
    super.dispose();
  }
}
