import 'dart:convert';
import 'dart:typed_data';

/// Frames use an 8-byte header + at most 12 bytes of payload; safe at ATT MTU 23.
class Wire {
  static const maxBytes = 16384;
  int? _id;
  int _next = 0, _length = 0;
  final List<int> _buffer = [];
  static List<Uint8List> encode(Map<String, dynamic> message, int id) {
    final bytes = utf8.encode(jsonEncode(message));
    if (bytes.length > maxBytes) throw const FormatException('消息过大');
    final packets = <Uint8List>[];
    for (var offset = 0, seq = 0; offset < bytes.length; offset += 12, seq++) {
      final end = (offset + 12).clamp(0, bytes.length);
      packets.add(
        Uint8List.fromList([
          0x50,
          1,
          (id >> 8) & 255,
          id & 255,
          seq >> 8,
          seq & 255,
          bytes.length >> 8,
          bytes.length & 255,
          ...bytes.sublist(offset, end),
        ]),
      );
    }
    return packets;
  }

  Map<String, dynamic>? add(List<int> packet) {
    try {
      if (packet.length < 9 ||
          packet.length > 20 ||
          packet[0] != 0x50 ||
          packet[1] != 1) {
        throw const FormatException('无效报文');
      }
      final id = packet[2] * 256 + packet[3];
      final seq = packet[4] * 256 + packet[5];
      final length = packet[6] * 256 + packet[7];
      if (length == 0 || length > maxBytes) throw const FormatException('报文过大');
      if (_id == null) {
        _id = id;
        _length = length;
      }
      if (id != _id || seq != _next || length != _length) {
        throw const FormatException('报文丢失或乱序');
      }
      _next++;
      _buffer.addAll(packet.sublist(8));
      if (_buffer.length > _length) throw const FormatException('报文长度不符');
      if (_buffer.length != _length) return null;
      final decoded = jsonDecode(utf8.decode(_buffer));
      reset();
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('报文格式不符');
      }
      return decoded;
    } catch (_) {
      reset();
      rethrow;
    }
  }

  void reset() {
    _id = null;
    _next = 0;
    _length = 0;
    _buffer.clear();
  }
}
