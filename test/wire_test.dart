import 'package:flutter_test/flutter_test.dart';
import 'package:pine_gomoku/domain/wire.dart';

void main() {
  test('Chinese profile survives 20-byte packet fragmentation', () {
    final message = <String, dynamic>{'v': 1, 'name': '松间旅人' * 20};
    final packets = Wire.encode(message, 17);
    final decoder = Wire();
    Map<String, dynamic>? result;
    for (final p in packets) {
      expect(p.length, lessThanOrEqualTo(20));
      result = decoder.add(p);
    }
    expect(result, message);
  });
  test('reject missing, reordered and corrupted frames', () {
    final packets = Wire.encode({'text': 'a' * 100}, 1);
    final decoder = Wire();
    decoder.add(packets.first);
    expect(() => decoder.add(packets[2]), throwsFormatException);
    expect(() => Wire().add([1, 2]), throwsFormatException);
  });
  test('reject oversized message before allocation', () {
    expect(() => Wire.encode({'text': 'a' * 20000}, 1), throwsFormatException);
  });
}
