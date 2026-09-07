import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../domain/profile.dart';

class PlayerAvatar extends StatelessWidget {
  static const icons = [
    Icons.eco_outlined,
    Icons.pets_outlined,
    Icons.forest_outlined,
    Icons.waves_outlined,
    Icons.dark_mode_outlined,
    Icons.local_florist_outlined,
    Icons.landscape_outlined,
    Icons.wb_sunny_outlined,
  ];
  final Profile profile;
  final double radius;
  const PlayerAvatar(this.profile, {super.key, this.radius = 25});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFFE5EBDE),
    child: profile.photo == null
        ? Icon(
            icons[profile.avatar],
            size: radius * 1.2,
            color: const Color(0xFF315B46),
            semanticLabel: Profile.avatars[profile.avatar],
          )
        : ClipOval(
            child: Image.memory(
              base64Decode(profile.photo!),
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              cacheWidth: 96,
              errorBuilder: (_, error, stack) =>
                  const Icon(Icons.person_outline),
            ),
          ),
  );
}

class ProfileEditor extends StatefulWidget {
  final Profile profile;
  const ProfileEditor(this.profile, {super.key});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );
  late int _avatar = widget.profile.avatar;
  late String? _photo = widget.profile.photo;
  String? _error;
  bool _busy = false;
  Future<void> pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 128,
        maxHeight: 128,
        imageQuality: 70,
      );
      if (file != null) {
        final image = img.decodeImage(await file.readAsBytes());
        if (image == null) throw const FormatException('无法读取这张图片');
        final square = img.copyResizeCropSquare(image, size: 64);
        final bytes = img.encodeJpg(square, quality: 65);
        if (bytes.length > 6000) throw const FormatException('图片过于复杂，请换一张图片');
        if (mounted) setState(() => _photo = base64Encode(bytes));
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取照片，请允许相册访问或选择其他照片');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void save() {
    try {
      final profile = Profile.fromJson({
        'name': _name.text.trim(),
        'avatar': _avatar,
        'photo': _photo,
      });
      Navigator.pop(context, profile);
    } catch (_) {
      setState(() => _error = '请输入 1–16 个字符的昵称');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '认识一下，棋友',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('你的资料会展示给同局的对手'),
            const SizedBox(height: 24),
            PlayerAvatar(Profile(avatar: _avatar, photo: _photo), radius: 38),
            TextButton.icon(
              onPressed: _busy ? null : pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_busy ? '正在处理…' : '从相册选择'),
            ),
            Wrap(
              spacing: 8,
              children: List.generate(
                Profile.avatars.length,
                (i) => Semantics(
                  label: '头像${i + 1}',
                  selected: _avatar == i && _photo == null,
                  child: IconButton(
                    onPressed: () => setState(() {
                      _avatar = i;
                      _photo = null;
                    }),
                    style: IconButton.styleFrom(
                      backgroundColor: _avatar == i && _photo == null
                          ? const Color(0xFFD9E5D9)
                          : Colors.transparent,
                    ),
                    tooltip: Profile.avatars[i],
                    icon: Icon(PlayerAvatar.icons[i], size: 25),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              maxLength: 16,
              decoration: const InputDecoration(
                labelText: '昵称',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : save,
                child: const Text('保存资料'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ),
  );
}
