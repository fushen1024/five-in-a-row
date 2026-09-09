import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';
import 'domain/game.dart';
import 'domain/profile.dart';
import 'domain/room.dart';
import 'services/ble_link.dart';
import 'session.dart';
import 'ui/board.dart';
import 'ui/profile_editor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PineApp());
}

const pine = Color(0xFF315B46);

class PineApp extends StatelessWidget {
  final bool autoScan;
  const PineApp({super.key, this.autoScan = true});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '松间五子棋',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F6F0),
      colorScheme: ColorScheme.fromSeed(
        seedColor: pine,
        surface: const Color(0xFFF7F6F0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F6F0),
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: pine,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
    home: Lobby(autoScan: autoScan),
  );
}

class Lobby extends StatefulWidget {
  final bool autoScan;
  const Lobby({super.key, required this.autoScan});
  @override
  State<Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<Lobby> with WidgetsBindingObserver {
  Profile _profile = const Profile();
  final Map<String, (BleDevice, DateTime)> _rooms = {};
  StreamSubscription<BleDevice>? _scanSub;
  Timer? _scanTimer;
  bool _busy = false, _scanning = false;
  String? _error;
  BleLink? _availableLink;
  GameSession? _availableSession;
  Future<void>? _preparing;
  Future<void>? _releasing;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      load().then((_) {
        if (widget.autoScan && mounted) unawaited(scan());
      }),
    );
  }

  Future<void> load() async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(
        'profile',
      );
      if (mounted && value != null) {
        setState(() => _profile = Profile.fromJson(jsonDecode(value)));
      }
    } catch (_) {
      /* A corrupt old profile falls back to the built-in identity. */
    }
  }

  Future<void> edit() async {
    if (_busy) return;
    setState(() => _busy = true);
    await stopScan();
    await releaseAvailability();
    if (!mounted) return;
    final profile = await showDialog<Profile>(
      context: context,
      builder: (_) => ProfileEditor(_profile),
    );
    if (!mounted) return;
    try {
      if (profile != null) {
        final ok = await (await SharedPreferences.getInstance()).setString(
          'profile',
          jsonEncode(profile.toJson()),
        );
        if (!ok) throw StateError('无法保存');
        if (mounted) setState(() => _profile = profile);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '资料保存失败，请重试');
    }
    if (mounted) {
      setState(() => _busy = false);
      if (widget.autoScan) unawaited(scan());
    }
  }

  Future<void> prepareAvailability() async {
    if (_availableLink != null) return;
    late final GameSession session;
    final link = BleLink(
      onMessage: (m) => unawaited(session.receive(m)),
      onError: (e) => session.fail(e),
    );
    session = GameSession(host: true, profile: _profile, send: link.send);
    _availableLink = link;
    _availableSession = session;
    session.addListener(incoming);
    try {
      await link.host();
    } catch (_) {
      session.removeListener(incoming);
      session.dispose();
      await link.close();
      _availableLink = null;
      _availableSession = null;
      if (mounted) setState(() => _error = '此设备暂时不能被发现，仍可搜索并加入其他棋友。');
    }
  }

  void incoming() {
    if (!mounted || _busy || !_foreground) return;
    if (_availableSession?.ready == true) {
      unawaited(play());
    } else if (_availableSession?.error != null) {
      setState(() => _error = _availableSession!.error);
      unawaited(releaseAvailability());
    }
  }

  Future<void> releaseAvailability() => _releasing ??= _releaseAvailability()
      .whenComplete(() => _releasing = null);

  Future<void> _releaseAvailability() async {
    await _preparing;
    final link = _availableLink, session = _availableSession;
    _availableLink = null;
    _availableSession = null;
    session?.removeListener(incoming);
    session?.dispose();
    await link?.close();
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    if (widget.autoScan) {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> scan() async {
    if (_busy || _scanning || !mounted || !_foreground) return;
    setState(() {
      _scanning = true;
      _error = null;
      _rooms.clear();
    });
    try {
      await BleLink.checkBluetooth();
      if (!mounted || !_scanning) return;
      _preparing = prepareAvailability();
      await _preparing;
      _preparing = null;
      if (!mounted || !_scanning || _busy || !_foreground) return;
      await _scanSub?.cancel();
      _scanSub = UniversalBle.scanStream.listen((device) {
        if (mounted && _scanning) {
          setState(() => _rooms[device.deviceId] = (device, DateTime.now()));
        }
      });
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [BleLink.serviceId]),
      );
      _scanTimer = Timer(
        const Duration(seconds: 20),
        () => unawaited(stopScan()),
      );
    } catch (e) {
      await stopScan();
      if (mounted) setState(() => _error = '未能搜索房间。请开启蓝牙并允许“附近设备”权限，然后重试。');
    }
  }

  Future<void> play({BleDevice? device, bool local = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    await stopScan();
    await _preparing;
    BleLink? initialLink;
    GameSession? initialSession;
    if (!local && device == null) {
      initialLink = _availableLink;
      initialSession = _availableSession;
      initialSession?.removeListener(incoming);
      _availableLink = null;
      _availableSession = null;
    } else {
      await releaseAvailability();
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MatchPage(
          profile: _profile,
          device: device,
          local: local,
          initialLink: initialLink,
          initialSession: initialSession,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _rooms.clear();
    });
    if (widget.autoScan) unawaited(scan());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _foreground = false;
      unawaited(stopScan().then((_) => releaseAvailability()));
    }
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (widget.autoScan && !_busy) {
        unawaited(releaseAvailability().then((_) => scan()));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _scanSub?.cancel();
    unawaited(releaseAvailability());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            children: [
              Row(
                children: [
                  const Icon(Icons.spa_outlined, color: pine, size: 30),
                  const SizedBox(width: 10),
                  const Text(
                    '松间',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7EDE4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bluetooth, size: 15, color: pine),
                        SizedBox(width: 4),
                        Text(
                          '无需网络',
                          style: TextStyle(color: pine, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              const Text(
                '不赶时间，\n下一盘好棋。',
                style: TextStyle(
                  fontSize: 36,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF263E31),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '在旅途中，和身边的人落子相逢。',
                style: TextStyle(color: Color(0xFF777D70), fontSize: 15),
              ),
              const SizedBox(height: 26),
              Container(
                height: 146,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EBDD),
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    const Positioned(
                      left: 22,
                      top: 27,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '一方棋盘 · 两位棋友',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: pine,
                            ),
                          ),
                          SizedBox(height: 9),
                          Text(
                            '蓝牙相连\n让片刻，慢下来',
                            style: TextStyle(
                              height: 1.7,
                              color: Color(0xFF6B7866),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (MediaQuery.sizeOf(context).width >= 360)
                      Positioned(
                        right: -32,
                        top: -38,
                        width: 205,
                        height: 205,
                        child: Transform.rotate(
                          angle: -.18,
                          child: ExcludeSemantics(
                            child: IgnorePointer(
                              child: Board(
                                game: heroGame(),
                                enabled: false,
                                onPlace: (_, y) {},
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    PlayerAvatar(_profile),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _profile.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            '准备好，来一局',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '编辑资料',
                      onPressed: edit,
                      icon: const Icon(Icons.edit_outlined, size: 21),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : () => play(),
                icon: const Icon(Icons.add),
                label: const Text('创建蓝牙房间'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => play(local: true),
                icon: const Icon(Icons.grid_on_outlined, size: 20),
                label: const Text('同机练习'),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  const Text(
                    '附近的房间',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _scanning ? null : scan,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(_scanning ? '搜索中…' : '重新搜索'),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFA35435)),
                  ),
                ),
              if (_rooms.isEmpty)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDFE3D8)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _scanning
                            ? Icons.bluetooth_searching
                            : Icons.people_outline,
                        size: 30,
                        color: const Color(0xFF8B9987),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _scanning ? '正在寻找身边的棋友' : '还没有发现可加入的房间',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '朋友打开游戏后即可被发现\n双方保持蓝牙开启，游戏留在前台',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.7,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final entry in _rooms.values.where(
                (e) => DateTime.now().difference(e.$2).inSeconds < 30,
              ))
                Card(
                  elevation: 0,
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth, color: pine),
                    title: Text(
                      '松间房间 · ${entry.$1.deviceId.replaceAll('-', '').replaceAll(':', '').substring(0, 4)}',
                    ),
                    subtitle: const Text('点击加入 · 每局随机执黑'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => play(device: entry.$1),
                  ),
                ),
              const SizedBox(height: 26),
              const Center(
                child: Text(
                  '十五路棋盘  /  五子连珠  /  相逢成趣',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF929989),
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Game heroGame() {
    final g = Game();
    for (final p in [(7, 7), (8, 7), (6, 8), (8, 6), (5, 9), (8, 8)]) {
      g.place(p.$1, p.$2, g.turn);
    }
    return g;
  }
}

class MatchPage extends StatefulWidget {
  final Profile profile;
  final BleDevice? device;
  final bool local;
  final BleLink? initialLink;
  final GameSession? initialSession;
  const MatchPage({
    super.key,
    required this.profile,
    this.device,
    required this.local,
    this.initialLink,
    this.initialSession,
  });
  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> with WidgetsBindingObserver {
  final Room _local = Room(hostBlack: Random.secure().nextBool());
  GameSession? _session;
  BleLink? _link;
  bool _allowPop = false;
  bool _starting = true;
  Room get room => widget.local ? _local : _session!.room;
  Game get game => room.game;
  bool get canAct => widget.local ? room.proposal == null : _session!.canAct;
  bool get currentActor => room.stoneFor(true) == game.turn;
  bool requestActor(String kind) => widget.local
      ? switch (kind) {
          'swap' => !room.hostBlack,
          _ => currentActor,
        }
      : _session!.host;
  bool canRequest(String kind) =>
      canAct &&
      (widget.local && kind == 'undo'
          ? room.canRequest(kind, true) || room.canRequest(kind, false)
          : room.canRequest(kind, requestActor(kind)));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialSession != null) {
      _link = widget.initialLink;
      _session = widget.initialSession;
      _session!.addListener(refresh);
      _starting = false;
      return;
    }
    if (!widget.local) {
      _link = BleLink(
        onMessage: (m) => unawaited(_session!.receive(m)),
        onError: (s) => _session!.fail(s),
      );
      _session = GameSession(
        host: widget.device == null,
        profile: widget.profile,
        send: _link!.send,
      )..addListener(refresh);
      unawaited(connect());
    }
  }

  Future<void> connect() async {
    try {
      if (widget.device == null) {
        await _link!.host();
      } else {
        await _link!.join(widget.device!);
        if (mounted) await _session!.hello();
      }
      _starting = false;
      refresh();
    } catch (_) {
      _session?.fail('蓝牙连接失败。请检查权限、蓝牙开关及设备广播支持，然后返回大厅重试。');
    }
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> place(int x, int y) async {
    if (widget.local) {
      setState(() => _local.apply('move', currentActor, {'x': x, 'y': y}));
    } else {
      await _session!.place(x, y);
    }
    unawaited(HapticFeedback.selectionClick());
  }

  String requestName(String kind) => switch (kind) {
    'undo' => '悔棋',
    'swap' => '换色',
    'draw' => '和棋',
    _ => '再来一局',
  };

  Future<void> request(String kind) async {
    if (!canRequest(kind)) return;
    if (!widget.local) {
      await _session!.request(kind);
      return;
    }
    var actor = requestActor(kind);
    if (kind == 'undo') {
      final selected = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('哪一方申请悔棋？'),
          content: const Text('选择申请方，再交给对方同意。棋盘将退至申请方上次落子前。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            for (final stone in [1, 2])
              OutlinedButton(
                onPressed: room.canRequest('undo', room.stoneFor(true) == stone)
                    ? () => Navigator.pop(context, room.stoneFor(true) == stone)
                    : null,
                child: Text('${stone == 1 ? '黑' : '白'}方申请'),
              ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      actor = selected;
    }
    setState(() => room.apply('request', actor, {'kind': kind}));
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          '${kind == 'rematch' ? '' : '${room.stoneFor(actor) == 1 ? '黑' : '白'}方'}${requestName(kind)}申请',
        ),
        content: Text(switch (kind) {
          'swap' => '请将设备交给对方确认。双方同意后交换黑白。',
          'undo' => '请将设备交给对方确认。双方同意后退至申请人上次落子前。',
          'draw' => '请将设备交给对方确认。双方同意后本局和棋，双方各得 0.5 分。',
          _ => '请双方确认是否再来一局。比分保留，新一局随机执黑。',
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(
      () => room.apply('respond', !actor, {
        'accept': accepted == true,
        if (kind == 'rematch' && accepted == true)
          'hostBlack': Random.secure().nextBool(),
      }),
    );
  }

  Future<void> resign() async {
    if (!canAct || room.proposal != null || game.finished) return;
    final actor = widget.local ? currentActor : _session!.host;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认认输？'),
        content: Text(
          '${room.stoneFor(actor) == 1 ? '黑' : '白'}方认输后，本局结束，对方获得 1 分。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续下棋'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认认输'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    if (widget.local) {
      setState(() => room.apply('resign', actor, {}));
    } else {
      await _session!.resign();
    }
  }

  Future<void> leave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('返回大厅？'),
        content: const Text('离开会结束当前对局。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续下棋'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('离开'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    if (_session != null) {
      try {
        await _session!.emit('leave').timeout(const Duration(seconds: 3));
      } catch (_) {
        /* Still close when the peer cannot receive the farewell. */
      }
    }
    await _link?.close();
    if (mounted) {
      setState(() => _allowPop = true);
      Navigator.pop(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !widget.local) {
      _session?.fail('游戏已进入后台，对局暂停。请返回大厅重新连接');
      if (_link != null) unawaited(_link!.close());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.removeListener(refresh);
    _session?.dispose();
    if (_link != null) unawaited(_link!.close());
    super.dispose();
  }

  String get status {
    if (_session?.error != null) return '连接已暂停';
    if (!widget.local && _starting) {
      return widget.device == null ? '正在创建蓝牙房间…' : '正在连接棋友…';
    }
    if (!widget.local && !_session!.ready) {
      return widget.device == null ? '房间已开启，等待棋友' : '正在连接，交换玩家资料…';
    }
    if (_session?.pending == true) return '正在同步操作…';
    if (room.proposal != null) return '正在协商${requestName(room.proposal!.kind)}';
    if (game.finished) {
      return game.winner == 0
          ? '棋逢对手，本局和棋'
          : '${room.resigned ? '${game.winner == 1 ? '白' : '黑'}方认输，' : ''}${game.winner == 1 ? '黑' : '白'}方获胜';
    }
    if (game.moves.isEmpty) return '黑方先行';
    return '轮到${game.turn == 1 ? '黑' : '白'}方落子';
  }

  @override
  Widget build(BuildContext context) {
    final remote = _session?.remote ?? const Profile(name: '等待棋友', avatar: 1);
    final host = widget.local || _session!.host ? widget.profile : remote;
    final guest = widget.local
        ? const Profile(name: '同机棋友', avatar: 1)
        : (_session!.host ? remote : widget.profile);
    final black = room.hostBlack ? host : guest;
    final white = room.hostBlack ? guest : host;
    final enabled = widget.local
        ? !game.finished && room.proposal == null
        : _session!.canPlay;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回大厅',
            onPressed: leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(widget.local ? '同机练习' : '蓝牙对弈'),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                widget.local ? Icons.grid_on : Icons.bluetooth,
                color: pine,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                children: [
                  Text(
                    '第 ${room.roundNumber} 局',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: pine,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: player(
                          black,
                          1,
                          room.hostBlack ? room.hostScore : room.guestScore,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            color: Color(0xFF9CA28F),
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: player(
                          white,
                          2,
                          room.hostBlack ? room.guestScore : room.hostScore,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: game.finished ? 27 : 19,
                        fontWeight: FontWeight.w700,
                        color: pine,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.local
                        ? '两人共用一台设备，轮流落子'
                        : !_session!.ready
                        ? '连接后随机分配黑白 · 蓝牙直连'
                        : '你执${_session!.myStone == 1 ? '黑' : '白'} · 无需网络，蓝牙直连',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  if (!widget.local && room.proposal != null) proposalCard(),
                  Board(
                    game: game,
                    enabled: enabled,
                    onPlace: (x, y) => unawaited(place(x, y)),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: canRequest('undo')
                            ? () => request('undo')
                            : null,
                        child: const Text('申请悔棋'),
                      ),
                      OutlinedButton(
                        onPressed: canRequest('swap')
                            ? () => request('swap')
                            : null,
                        child: const Text('申请换色'),
                      ),
                      OutlinedButton(
                        onPressed: canRequest('draw')
                            ? () => request('draw')
                            : null,
                        child: const Text('申请和棋'),
                      ),
                      OutlinedButton(
                        onPressed:
                            canAct && room.proposal == null && !game.finished
                            ? resign
                            : null,
                        child: const Text('认输'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '自由规则 · 连成五子即胜 · 和棋需双方同意',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7F8778),
                          ),
                        ),
                      ),
                      Text(
                        '已落 ${game.moves.length} 手',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7F8778),
                        ),
                      ),
                    ],
                  ),
                  if (_session?.error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2E4D9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _session!.error!,
                        style: const TextStyle(color: Color(0xFF924C30)),
                      ),
                    ),
                  if (game.finished)
                    Container(
                      margin: const EdgeInsets.only(top: 24),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7EDDF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.emoji_events_outlined,
                            size: 34,
                            color: pine,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            game.winner == 0
                                ? '这一局，不分伯仲'
                                : '${game.winner == 1 ? black.name : white.name}，好棋！',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: canRequest('rematch')
                                ? () => request('rematch')
                                : null,
                            child: const Text('再来一局'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    '友好协商，享受此刻。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFFA1A694)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget proposalCard() {
    final proposal = room.proposal!;
    final mine = proposal.byHost == _session!.host;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE7EDDF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            mine
                ? '已申请${requestName(proposal.kind)}，等待对方同意'
                : '对方申请${requestName(proposal.kind)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(switch (proposal.kind) {
            'undo' => '同意后退至申请人上次落子前。',
            'swap' => '同意后交换黑白，比分仍属于原玩家。',
            'draw' => '同意后本局和棋，双方各得 0.5 分。',
            _ => '同意后保留比分，再开一局，随机执黑。',
          }, textAlign: TextAlign.center),
          if (!mine)
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: _session!.canAct
                      ? () => _session!.respond(false)
                      : null,
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: _session!.canAct
                      ? () => _session!.respond(true)
                      : null,
                  child: const Text('同意'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget player(Profile profile, int stone, double score) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: !game.finished && game.turn == stone
            ? pine.withValues(alpha: .45)
            : Colors.transparent,
      ),
    ),
    child: Column(
      children: [
        PlayerAvatar(profile, radius: 23),
        const SizedBox(height: 9),
        Text(
          profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          stone == 1 ? '● 黑方' : '○ 白方',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          '${score == score.truncateToDouble() ? score.toInt() : score} 分',
          style: const TextStyle(color: pine, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
