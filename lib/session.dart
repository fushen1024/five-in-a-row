import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'domain/game.dart';
import 'domain/profile.dart';
import 'domain/room.dart';

typedef SendMessage = Future<void> Function(Map<String, dynamic> message);

class GameSession extends ChangeNotifier {
  final bool host;
  final Profile profile;
  final SendMessage send;
  Profile? remote;
  Room room = Room(hostBlack: true);
  Game get game => room.game;
  String round = '';
  String? error;
  bool ready = false, pending = false;
  bool _disposed = false;
  int _revision = 0;
  int? _awaitingAck;
  Timer? _heartbeat, _deadline, _proposalTimer;
  DateTime _lastSeen = DateTime.now();
  Future<void> _inbox = Future.value();
  GameSession({required this.host, required this.profile, required this.send});
  int get myStone => room.stoneFor(host);
  bool get canAct => ready && error == null && !pending && !_disposed;
  bool get canPlay =>
      canAct && room.proposal == null && !game.finished && game.turn == myStone;

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> emit(String type, [Map<String, dynamic> data = const {}]) async {
    if (_disposed || error != null) return;
    try {
      await send({'v': 2, 'type': type, ...data});
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

  void _waitAck() {
    pending = true;
    _awaitingAck = _revision;
    deadline();
    changed();
  }

  Future<void> _ack() => emit('ack', {'round': round, 'rev': _revision});

  Future<void> receive(Map<String, dynamic> message) {
    _inbox = _inbox.then((_) => _receive(message));
    return _inbox;
  }

  Future<void> _receive(Map<String, dynamic> m) async {
    if (_disposed || error != null) return;
    try {
      if (m['v'] != 2) throw const FormatException('双方均需升级到 2.0');
      _lastSeen = DateTime.now();
      switch (m['type']) {
        case 'hello':
          if (!host || remote != null) throw const FormatException('重复握手');
          remote = Profile.fromJson(m['profile']);
          round =
              '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
          room = Room(hostBlack: Random.secure().nextBool());
          _waitAck();
          await emit('welcome', {
            'round': round,
            'hostBlack': room.hostBlack,
            'profile': profile.toJson(),
          });
        case 'welcome':
          if (host ||
              remote != null ||
              m['round'] is! String ||
              (m['round'] as String).isEmpty ||
              m['hostBlack'] is! bool) {
            throw const FormatException('无效开局');
          }
          remote = Profile.fromJson(m['profile']);
          round = m['round'];
          room = Room(hostBlack: m['hostBlack']);
          ready = true;
          _deadline?.cancel();
          startHeartbeat();
          await _ack();
        case 'ack':
          if (!host ||
              remote == null ||
              _awaitingAck == null ||
              m['round'] != round ||
              m['rev'] != _awaitingAck) {
            return;
          }
          _awaitingAck = null;
          pending = false;
          ready = true;
          _deadline?.cancel();
          startHeartbeat();
          _scheduleProposalExpiry();
        case 'command':
          if (!host || remote == null || m['round'] != round) return;
          if (!canAct ||
              m['rev'] != _revision ||
              m['action'] is! String ||
              m['data'] is! Map<String, dynamic>) {
            await emit('rejected', {'round': round, 'rev': _revision});
            return;
          }
          if (!await _commit(m['action'], false, m['data'])) {
            await emit('rejected', {'round': round, 'rev': _revision});
          }
        case 'event':
          if (host || !ready || m['round'] != round || m['rev'] is! int) {
            throw const FormatException('无效同步');
          }
          if (m['rev'] <= _revision) {
            await _ack();
            return;
          }
          if (m['rev'] != _revision + 1 ||
              m['actor'] is! bool ||
              m['action'] is! String ||
              m['data'] is! Map<String, dynamic> ||
              !room.apply(m['action'], m['actor'], m['data'])) {
            throw const FormatException('操作序列不一致');
          }
          _revision = m['rev'];
          pending = false;
          _deadline?.cancel();
          await _ack();
        case 'rejected':
          if (!host && m['round'] == round && m['rev'] == _revision) {
            pending = false;
            _deadline?.cancel();
          }
        case 'ping':
          if (remote != null) await emit('pong');
        case 'pong':
          break;
        case 'leave':
          fail('对方已离开，请返回大厅重新建房');
        default:
          throw const FormatException('未知消息');
      }
      changed();
    } catch (_) {
      fail('对局数据异常或版本不兼容，请确认双方均已升级到 2.0 后重新连接');
    }
  }

  Future<bool> _commit(
    String action,
    bool actor,
    Map<String, dynamic> data,
  ) async {
    final approved = Map<String, dynamic>.from(data);
    // Only the host chooses randomness, never a peer-provided random result.
    if (action == 'respond' &&
        room.proposal?.kind == 'rematch' &&
        approved['accept'] == true) {
      approved['hostBlack'] = Random.secure().nextBool();
    }
    if (!room.apply(action, actor, approved)) return false;
    _proposalTimer?.cancel();
    _revision++;
    _waitAck();
    await emit('event', {
      'round': round,
      'rev': _revision,
      'action': action,
      'actor': actor,
      'data': approved,
    });
    return true;
  }

  void _scheduleProposalExpiry() {
    _proposalTimer?.cancel();
    final proposal = room.proposal;
    if (!host || proposal == null) return;
    _proposalTimer = Timer(const Duration(seconds: 30), () {
      if (canAct && identical(room.proposal, proposal)) {
        // Timeout may only decline, never grant consent on behalf of a player.
        unawaited(_commit('respond', !proposal.byHost, {'accept': false}));
      }
    });
  }

  Future<void> _command(String action, Map<String, dynamic> data) async {
    if (!canAct) return;
    if (host) {
      await _commit(action, true, data);
    } else {
      pending = true;
      deadline();
      changed();
      await emit('command', {
        'round': round,
        'rev': _revision,
        'action': action,
        'data': data,
      });
    }
  }

  Future<void> place(int x, int y) async {
    if (!canPlay ||
        x < 0 ||
        y < 0 ||
        x >= Game.size ||
        y >= Game.size ||
        game.at(x, y) != 0) {
      return;
    }
    await _command('move', {'x': x, 'y': y});
  }

  Future<void> request(String kind) async {
    if (!room.canRequest(kind, host)) return;
    await _command('request', {'kind': kind});
  }

  Future<void> respond(bool accept) async {
    if (room.proposal == null || room.proposal!.byHost == host) return;
    await _command('respond', {'accept': accept});
  }

  Future<void> resign() async {
    if (game.finished || room.proposal != null) return;
    await _command('resign', {});
  }

  void fail(String reason) {
    if (_disposed || error != null) return;
    error = reason;
    ready = false;
    pending = false;
    _heartbeat?.cancel();
    _deadline?.cancel();
    _proposalTimer?.cancel();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _deadline?.cancel();
    _proposalTimer?.cancel();
    super.dispose();
  }
}
