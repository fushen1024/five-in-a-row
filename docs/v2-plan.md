# 松间五子棋 2.0 实施计划

用户已确认：悔棋需对方同意，退至申请人上次落子前；认输确认后结算；双方同意后原房重开；每局随机执黑，首手前白方可申请交换；胜者 1 分、和棋各 0.5 分，玩家比分在房间保留、离房清零。

## 结构与步骤

1. `lib/domain/room.dart`：房间状态和经过校验的操作，管理玩家颜色、局数、申请和比分。为悔棋、拒绝、自批禁止、重开、换色、重复结算写失败测试，再实现。
2. `lib/session.dart`：协议升级为 v2；房主顺序处理命令，广播带递增版本的操作，访客重放并确认。版本隔离、旧消息、操作冲突、超时均不允许继续非法落子。双方会话集成测试验证整局、认输、悔棋、连局。
3. `lib/main.dart`：同步展示房间比分、颜色和申请，增加悔棋、认输确认、换色和再开按钮；同机练习复用房间规则。为按钮和布局增加交互测试。
4. `pubspec.yaml` 改为 `2.0.0+2`，保留应用标识和本机原签名。更新 README 和真机验收说明，保留用户修改。
5. 静态分析、全部自动测试、Release APK 构建；比对 1.0/2.0 签名证书、包名、版本号。提交功能代码并推送至原仓库，发布 v2.0.0 APK 与 SHA-256。

## 同步接口

Room：`game`, `hostBlack`, `roundNumber`, `hostScore`, `guestScore`, `proposal`；`stoneFor(bool host)`；`apply(String action, bool actor, Map<String,dynamic> data)`；申请有 `kind`（undo/swap/rematch）与 `byHost`。

GameSession：保留 `game`, `ready`, `pending`, `error`, `myStone`, `canPlay`, `place`；新增 `room`, `canAct`, `request(String kind)`, `respond(bool accept)`, `resign()`。断线冻结操作；申请期间暂停棋盘，房主在 30 秒无人响应时同步取消申请。

## 发布限制

两端均需 2.0；不伪称真机验收通过。安卓覆盖升级以相同 applicationId、相同证书、递增 versionCode 验证；真实安装需手机。iOS 本次维持源码与云端编译检查，不发布未签名 IPA。

## 完成记录

房间规则、v2 协议、全部界面及覆盖升级配置完成。46 项测试、静态检查及 Release 构建通过。最终独立审查已复核同机申请人选择修正。签名与应用标识同 1.0，versionCode 为 2。详见 verification.md。发布沿用用户已授权的原 GitHub 仓库，不另行要求发布确认。
