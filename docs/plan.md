# 双平台五子棋实施计划

目标：实现开发文档五项需求并提供可复现构建、测试与真机验收说明。
设计：见 design.md。技术：Flutter、Dart、universal_ble、shared_preferences、image_picker。

1. 建立 Flutter Android/iOS 工程。先为棋盘边界、回合、四方向胜利、重复落子、终局落子写测试，再实现 lib/domain/game.dart。
2. 先测试报文分片、中文往返、乱序与超长拒绝，再实现 lib/domain/wire.dart。每片不超过 20 字节。
3. 实现 lib/services/ble_link.dart，封装扫描、广播、连接、通知、清理；实现可注入传输的 lib/session.dart，以双端控制器测试验证权威同步和错误状态。
4. 实现资料持久化、相册头像压缩与大小限制，完成大厅、资料编辑、棋盘与结果界面。
5. 配置 Android/iOS 蓝牙和相册说明；运行格式化、静态检查、规则与界面测试。编写安装和真机验收说明，准确记录未能执行的检查。

不发布应用商店，不配置虚构的签名证书。当前 Windows 环境不能执行 iOS 构建。

## 执行结果

上述 1–5 项源码与配置实现已完成；24 项自动测试通过，静态分析无问题，Android debug APK 构建成功。iOS 构建和真实手机无线互通受当前设备环境限制尚未执行，详见 verification.md 与 device-testing.md。
