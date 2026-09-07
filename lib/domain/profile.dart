import 'dart:convert';

class Profile {
  static const avatars = ['新叶', '猫咪', '森林', '浪花', '月亮', '花朵', '山峰', '暖阳'];
  final String name;
  final int avatar;
  final String? photo;
  const Profile({this.name = '松间旅人', this.avatar = 0, this.photo});
  Map<String, dynamic> toJson() => {
    'name': name,
    'avatar': avatar,
    'photo': photo,
  };
  static Profile fromJson(dynamic json) {
    if (json is! Map || json['name'] is! String || json['avatar'] is! int) {
      throw const FormatException('玩家资料无效');
    }
    final name = (json['name'] as String).trim();
    final avatar = json['avatar'] as int;
    final photo = json['photo'];
    if (name.isEmpty ||
        name.runes.length > 16 ||
        avatar < 0 ||
        avatar >= avatars.length ||
        (photo != null && (photo is! String || photo.length > 8200))) {
      throw const FormatException('玩家资料超出限制');
    }
    if (photo != null) {
      final bytes = base64Decode(photo as String);
      if (bytes.length < 3 ||
          bytes[0] != 255 ||
          bytes[1] != 216 ||
          bytes[2] != 255) {
        throw const FormatException('头像必须为 JPEG');
      }
    }
    return Profile(name: name, avatar: avatar, photo: photo as String?);
  }
}
