# 验证记录

日期：2026-09-07。环境：Windows 11、Flutter 3.47.2、Dart 3.13.2、JDK 21。

| 检查 | 结果 |
| --- | --- |
| Flutter 静态分析 | 通过，无问题 |
| 自动测试 | 24 项通过 |
| Android Manifest / iOS Info.plist 解析 | 通过 |
| Android 测试 APK 构建 | 通过，flutter build apk --debug，退出码 0 |
| APK 签名验证 | 通过，APK Signature Scheme v2，1 个开发签名 |
| APK 应用信息 | 松间五子棋；com.pinegames.pine_gomoku；1.0.0；最低 API 24；arm64-v8a / armeabi-v7a / x86_64 |
| iOS 原生构建与签名 | 未执行，当前无 Mac / Xcode |
| Android/iOS 四组蓝牙互通 | 未执行，当前无两台连接的真机 |

自动测试涵盖：四方向胜利、满盘和棋、边界与回合校验、重复落子、终局拒绝落子、非法棋谱、中文消息分片、报文乱序和大小限制、资料校验、双端整局同步、未请求确认与非法开局防护、握手超时、断线冻结、蓝牙 peripheral 就绪等待、资料保存和页面交互。界面在 390×844、320×568、844×390 尺寸验证。

独立代码审查发现并修复：退出消息必须发送完成后释放连接；iOS 首次初始化需要等待 peripheral ready。没有将自动测试当作真实无线连接测试。

真实 Flutter 界面截图位于 screenshots/lobby.png 与 screenshots/match.png；通过 widget 渲染生成，不是设计稿。真机验收步骤见 device-testing.md。

Android APK：157,041,184 字节。SHA-256：`C828D6A863BC1C3F31F68D4F34D8C9A69FFDA1A448B878AB4C5E579A05190816`。

测试包保留 Flutter debug 所需的 INTERNET 权限，游戏业务本身不依赖互联网。正式上架还需正式签名、隐私披露和真机验收；当前未发布到任何应用商店。
