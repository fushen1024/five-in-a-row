import 'dart:async';
import 'package:universal_ble/universal_ble.dart';
import '../domain/wire.dart';

Future<void> waitForPeripheralReady(
  Future<PeripheralReadinessState> Function() readState,
) async {
  for (var attempt = 0; attempt < 25; attempt++) {
    final state = await readState();
    if (state == PeripheralReadinessState.ready) return;
    if (state != PeripheralReadinessState.unknown) {
      throw StateError('蓝牙广播尚不可用，请检查蓝牙权限和设备支持');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('蓝牙初始化超时，请重试');
}

class BleLink {
  static const serviceId = '849d0001-50b7-4a43-85ea-3d5b03c8a014';
  static const inputId = '849d0002-50b7-4a43-85ea-3d5b03c8a014';
  static const outputId = '849d0003-50b7-4a43-85ea-3d5b03c8a014';
  final void Function(Map<String, dynamic>) onMessage;
  final void Function(String) onError;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Wire _wire = Wire();
  String? _peer;
  bool _host = false, _closed = false;
  int _id = 0;
  BleCharacteristic? _input;
  Future<void> _outbox = Future.value();
  Future<void>? _closing;
  Timer? _handshake;
  BleLink({required this.onMessage, required this.onError});

  static Future<void> checkBluetooth() async {
    await UniversalBle.requestPermissions();
    if (await UniversalBle.getBluetoothAvailabilityState() !=
        AvailabilityState.poweredOn) {
      throw StateError('请在系统设置中打开蓝牙，再点击重试');
    }
  }

  void _accept(List<int> bytes) {
    if (_closed) return;
    try {
      final message = _wire.add(bytes);
      if (message != null) {
        _handshake?.cancel();
        onMessage(message);
      }
    } catch (_) {
      onError('蓝牙报文丢失，请重新连接');
    }
  }

  Future<void> host() async {
    _ensureOpen();
    _host = true;
    await checkBluetooth();
    _ensureOpen();
    final caps = await UniversalBlePeripheral.getCapabilities();
    _ensureOpen();
    if (!caps.supportsPeripheralMode ||
        !caps.supportsTargetedCharacteristicUpdate) {
      throw StateError('此设备不能创建蓝牙房间，请尝试加入另一台手机的房间');
    }
    await waitForPeripheralReady(() {
      _ensureOpen();
      return UniversalBlePeripheral.getAvailabilityState();
    });
    await UniversalBle.stopScan();
    _ensureOpen();
    await UniversalBlePeripheral.clearServices();
    _ensureOpen();
    UniversalBlePeripheral.setWriteRequestHandlers((
      device,
      characteristic,
      offset,
      value,
    ) {
      if (!_closed &&
          device == _peer &&
          characteristic == inputId &&
          offset == 0 &&
          value != null) {
        _accept(value);
      }
      return PeripheralWriteRequestResult();
    });
    _subscriptions.add(
      UniversalBlePeripheral.characteristicSubscriptionStream.listen((event) {
        if (event.characteristicId != outputId || _closed) return;
        if (event.isSubscribed && _peer == null) {
          _peer = event.deviceId;
          _handshake = Timer(
            const Duration(seconds: 30),
            () => onError('对方连接超时，请重新创建房间'),
          );
          unawaited(
            UniversalBlePeripheral.stopAdvertising().catchError((Object _) {}),
          );
        } else if (!event.isSubscribed && event.deviceId == _peer) {
          onError('对方已断开连接，请返回大厅');
        }
      }),
    );
    _subscriptions.add(
      UniversalBlePeripheral.connectionStateStream.listen((event) {
        if (event.deviceId == _peer && !event.connected && !_closed) {
          onError('连接已断开，请返回大厅');
        }
      }),
    );
    _subscriptions.add(
      UniversalBlePeripheral.advertisingStateStream.listen((event) {
        if (event.error != null && !_closed) onError('房间广播失败，请重新创建房间');
      }),
    );
    await UniversalBlePeripheral.addService(
      BlePeripheralService(
        uuid: serviceId,
        characteristics: [
          BlePeripheralCharacteristic(
            uuid: inputId,
            properties: [CharacteristicProperty.write],
            permissions: [PeripheralAttributePermission.writeable],
          ),
          BlePeripheralCharacteristic(
            uuid: outputId,
            properties: [CharacteristicProperty.notify],
            permissions: [PeripheralAttributePermission.readable],
          ),
        ],
      ),
    );
    _ensureOpen();
    await UniversalBlePeripheral.startAdvertising(
      services: [serviceId],
      localName: 'Pine',
    );
  }

  Future<void> join(BleDevice device) async {
    _ensureOpen();
    await checkBluetooth();
    _ensureOpen();
    await UniversalBle.stopScan();
    _ensureOpen();
    _peer = device.deviceId;
    _subscriptions.add(
      device.connectionStream.listen((connected) {
        if (!connected && !_closed) onError('连接已断开，请返回大厅');
      }),
    );
    await device.connect();
    _ensureOpen();
    await device.discoverServices();
    _ensureOpen();
    _input = await device.getCharacteristic(inputId, service: serviceId);
    final output = await device.getCharacteristic(outputId, service: serviceId);
    _ensureOpen();
    _subscriptions.add(output.onValueReceived.listen(_accept));
    await output.notifications.subscribe();
  }

  Future<void> send(Map<String, dynamic> message) {
    final operation = _outbox.then((_) async {
      if (_closed || _peer == null) throw StateError('蓝牙未连接');
      final packets = Wire.encode(message, _id++ % 65536);
      for (final packet in packets) {
        if (_closed) throw StateError('蓝牙已断开');
        if (_host) {
          await UniversalBlePeripheral.updateCharacteristicValue(
            characteristicId: outputId,
            value: packet,
            deviceId: _peer,
          );
          // Keep a conservative rate to avoid overflowing peripheral notify buffers.
          await Future<void>.delayed(const Duration(milliseconds: 10));
        } else {
          await _input!.write(packet, withResponse: true);
        }
      }
    });
    _outbox = operation.catchError((Object _) {});
    return operation;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('连接操作已取消');
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _handshake?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _wire.reset();
    if (_host) {
      UniversalBlePeripheral.setWriteRequestHandlers(null);
      try {
        await UniversalBlePeripheral.stopAdvertising();
      } catch (_) {
        /* Bluetooth may be off. */
      }
      try {
        await UniversalBlePeripheral.clearServices();
      } catch (_) {
        /* Already removed. */
      }
    } else if (_peer != null) {
      try {
        await UniversalBle.disconnect(_peer!);
      } catch (_) {
        /* Already disconnected. */
      }
    }
  }
}
