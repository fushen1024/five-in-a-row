import 'package:flutter_test/flutter_test.dart';
import 'package:pine_gomoku/domain/profile.dart';

void main() {
  test('default profile and Chinese nickname roundtrip', () {
    final p = Profile.fromJson(const Profile().toJson());
    expect(p.name, '松间旅人');
    expect(p.avatar, 0);
    expect(p.photo, isNull);
    expect(Profile.fromJson({'name': '  云间棋友  ', 'avatar': 7}).name, '云间棋友');
  });
  test('invalid profile is rejected before it reaches UI', () {
    for (final p in [
      {'name': '', 'avatar': 0},
      {'name': '松' * 17, 'avatar': 0},
      {'name': '松', 'avatar': -1},
      {'name': '松', 'avatar': 8},
      {'name': '松', 'avatar': 0, 'photo': 'not-an-image'},
      {'name': '松', 'avatar': 0, 'photo': 'a' * 9000},
    ]) {
      expect(() => Profile.fromJson(p), throwsFormatException);
    }
  });
}
