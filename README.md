# flutter_mimc

小米 MIMC 的 Flutter 多平台插件，提供统一的 Dart API，支持 Android、iOS、
Web、macOS、Windows 和 Linux。

当前版本：`2.0.0-dev.3`（预发布版）。

> 普通消息、登录和服务端 ACK 已通过 Android 真机验证。RTS 对端数据接收以及
> Windows/Linux 目标机集成尚未完成生产验收，因此当前版本不应直接作为稳定版使用。

## 支持平台

| 平台 | 底层 SDK | 是否内置 | 已实现能力 |
|---|---|:---:|---|
| Android | MIMC Java SDK 2.0.8 | 是 | 单聊、普通群、在线消息、无限群、离线拉取、RTS、多人 RTS |
| iOS | MIMC SDK 2.2.7 | 是 | 单聊、普通群、在线消息、无限群、离线拉取、RTS、多人 RTS |
| Web | MIMC WebJS SDK 1.0.3 | 是 | 单聊、普通群、无限群、离线拉取 |
| macOS | MIMC C++ SDK | 是 | 单聊、普通群、在线消息、点对点 RTS |
| Windows | MIMC C++ SDK | 否 | 单聊、普通群、在线消息、点对点 RTS |
| Linux | MIMC C++ SDK | 否 | 单聊、普通群、在线消息、点对点 RTS |

平台差异：

- WebJS SDK 没有在线消息和 RTS 接口。
- C++ SDK 的公开 C API 没有无限群、离线拉取通知和多人 RTS 频道。
- 不支持的方法会抛出 `MimcException(code: 'unsupported')`。
- 业务代码应调用 `getCapabilities()` 判断能力，不要只根据操作系统名称判断。

## 环境要求

- Dart 3.3 或更高
- Flutter 3.24 或更高
- Android：API 21 或更高、JDK 17
- iOS：iOS 12 或更高
- macOS：macOS 10.14 或更高
- Windows/Linux：CMake 3.16 或更高、C++ 编译环境

## 安装

当前版本从 GitHub Tag 安装：

```yaml
dependencies:
  flutter_mimc:
    git:
      url: https://github.com/owxo/flutter_mimc.git
      # 生产项目请固定到已验证的完整提交 SHA。
      ref: <full-commit-sha>
```

然后执行：

```bash
flutter pub get
```

建议固定具体 Tag，不要让正式项目直接依赖持续变化的 `master`。

## Token 后端

MIMC 的 AppKey 和 AppSecret 必须保存在业务服务端，不能写入 Flutter 客户端。

推荐流程：

```text
Flutter 登录业务账号
    ↓
携带业务登录 Token 请求自己的后端
    ↓
后端验证用户身份，并取得数据库中的用户唯一 ID
    ↓
后端使用 AppID、AppKey、AppSecret 请求小米 Token 接口
    ↓
将小米返回的完整 JSON 原样返回 Flutter
```

要求：

1. `appAccount` 必须由后端认证用户的唯一 ID 生成。
2. 不允许客户端提交任意 `appAccount` 冒充其他用户。
3. Flutter 的 `tokenProvider` 必须返回小米 Token 接口的完整 JSON。
4. 不能只返回 `data.token`。
5. 不要把业务用户 Token 通过 `--dart-define` 编译进正式安装包。

TokenProvider 示例：

```dart
Future<String> fetchCompleteMimcTokenJson() async {
  // 调用自己的业务后端。
  // 请求头携带当前用户的业务登录 Token。
  // 返回值必须是小米 Token 接口的完整原始 JSON 字符串。
  return response.body;
}
```

仓库提供两个通用后端参考实现：

```text
example/backend/fastadmin/
example/backend/php/
```

示例只包含通用占位符，不包含任何正式域名、AppID、账号或密钥。

## 初始化和登录

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_mimc/flutter_mimc.dart';

final FlutterMimc mimc = FlutterMimc.instance;

final StreamSubscription<MimcEvent> subscription =
    mimc.events.listen((MimcEvent event) {
  switch (event) {
    case MimcConnectionChanged(:final state, :final description):
      print('连接状态：$state，说明：$description');

    case MimcMessageReceived(:final message):
      print(
        '收到消息：${utf8.decode(message.payload, allowMalformed: true)}',
      );

    case MimcServerAckReceived(:final ack):
      print('服务端 ACK：packetId=${ack.packetId} code=${ack.code}');

    case MimcSendTimedOut(:final message):
      print('发送超时：${message.packetId}');

    default:
      break;
  }
});

await mimc.initialize(
  config: const MimcConfig(
    // 跨平台项目建议始终使用十进制字符串，避免 Web 整数精度丢失。
    appId: '<MIMC_APP_ID>',

    // 必须是后端认证用户的唯一 ID，并与 Token 响应一致。
    appAccount: '<BACKEND_USER_ID>',

    // 同一账号的不同设备建议使用不同且稳定的 resource。
    resource: 'mobile',

    debug: false,
  ),
  tokenProvider: fetchCompleteMimcTokenJson,
);

await mimc.login();
```

`login()` 表示登录请求已经提交。是否真正在线，应以
`MimcConnectionChanged(state: MimcConnectionState.online)` 或
`await mimc.isOnline()` 为准。

建议在调用 `login()` 之前订阅 `events`，避免错过快速返回的状态事件。

## 发送单聊消息

```dart
final String packetId = await mimc.sendMessage(
  toAccount: '<RECIPIENT_ACCOUNT>',
  payload: utf8.encode('{"type":"text","content":"hello"}'),
  bizType: 'chat.text',
  store: true,
);

print('消息已提交：$packetId');
```

`sendMessage()` 返回 packetId，只表示本地 SDK 接受了发送请求。服务端是否成功处理，
需要匹配后续的 `MimcServerAckReceived`；发送超时会收到 `MimcSendTimedOut`。

## 普通群消息

```dart
await mimc.sendGroupMessage(
  topicId: 123456789,
  payload: utf8.encode('hello group'),
  bizType: 'chat.group.text',
  store: true,
);
```

## 在线消息

```dart
await mimc.sendOnlineMessage(
  toAccount: '<RECIPIENT_ACCOUNT>',
  payload: utf8.encode('online only'),
);
```

在线消息只投递给当前在线设备。WebJS SDK 不支持此功能。

## 无限群

```dart
final int topicId = await mimc.createUnlimitedGroup('room-name');

await mimc.joinUnlimitedGroup(topicId);

await mimc.sendUnlimitedGroupMessage(
  topicId: topicId,
  payload: utf8.encode('hello room'),
);

await mimc.quitUnlimitedGroup(topicId);

// 仅群主可以解散：
// await mimc.dismissUnlimitedGroup(topicId);
```

无限群只在 Android、iOS 和 Web 报告支持。

## 查询平台能力

```dart
final Set<MimcCapability> capabilities = await mimc.getCapabilities();

if (capabilities.contains(MimcCapability.unlimitedGroup)) {
  // 显示无限群功能。
}

if (capabilities.contains(MimcCapability.realtimeStream)) {
  // 显示点对点 RTS 功能。
}
```

可查询的能力包括：

```dart
MimcCapability.message
MimcCapability.groupMessage
MimcCapability.onlineMessage
MimcCapability.unlimitedGroup
MimcCapability.offlinePull
MimcCapability.realtimeStream
MimcCapability.realtimeChannel
```

## RTS 实时数据

MIMC RTS 只负责传输音频、视频二进制帧，不负责以下功能：

- 麦克风和摄像头采集
- 音视频编解码
- 回声消除
- 视频渲染
- Web 音视频支持

业务项目需要自行接入相应媒体组件。

设置来电策略：

```dart
await mimc.setRtsIncomingCallPolicy(
  MimcRtsIncomingCallPolicy.accept,
  description: 'ready',
);
```

发起呼叫：

```dart
final int callId = await mimc.dialRtsCall(
  toAccount: '<RECIPIENT_ACCOUNT>',
  toResource: '<RECIPIENT_RESOURCE>',
  appContent: utf8.encode('{"type":"call"}'),
);
```

发送 RTS 数据：

```dart
final int dataId = await mimc.sendRtsData(
  callId: callId,
  payload: encodedFrame,
  dataType: MimcRtsDataType.audio,
  priority: MimcRtsDataPriority.p1,
  canBeDropped: false,
  resendCount: 1,
  channelType: MimcRtsChannelType.automatic,
  context: 'audio-frame',
);
```

关闭呼叫：

```dart
await mimc.closeRtsCall(callId, reason: 'finished');
```

RTS 事件仍通过 `mimc.events` 返回，包括：

- `MimcRtsCallIncoming`
- `MimcRtsCallAnswered`
- `MimcRtsCallClosed`
- `MimcRtsDataReceived`
- `MimcRtsDataSendResult`
- `MimcRtsP2pResult`

当前预发布版已经实现呼叫建立和发送结果回调，但跨设备的对端数据接收还没有完成
生产验收。`MimcRtsDataSendResult(success: true)` 不等于对端 Flutter 已收到数据。

WebJS SDK 没有 RTS API。需要覆盖 Web 的全平台音视频时，建议使用 MIMC 负责消息和
信令，使用 WebRTC/LiveKit 等方案承载实际音视频轨道。

## Web 配置

Web 端会自动加载插件内置的 WebJS 文件，无需修改 `web/index.html`：

```text
assets/packages/flutter_mimc/assets/web/mimc-min_1_0_3.js
```

注意：

- AppID 必须使用十进制字符串。
- Web 发送的 payload 必须是合法 UTF-8。
- Token API 跨域时，后端必须正确处理 CORS 和 OPTIONS 预检。
- HTTPS 页面不能请求 HTTP Token 接口。
- Web 不支持在线消息和 RTS。

## iOS 配置

iOS 2.2.7 SDK 的 RTS resolver 会访问 HTTP 地址。使用 RTS 时，需要在宿主
`Info.plist` 添加仅针对小米 resolver 域名的 ATS 例外：

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>resolver.msg.xiaomi.net</key>
    <dict>
      <key>NSIncludesSubdomains</key><true/>
      <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
    </dict>
  </dict>
</dict>
```

不要使用全局 `NSAllowsArbitraryLoads`。

小米最后公开的 iOS framework 没有 `arm64-simulator` slice。插件会同时在 Pod
目标和宿主目标的 Simulator 构建中排除 arm64，并使用 framework 的 x86_64
Simulator slice；真机构建仍然使用 arm64。

## macOS 配置

macOS 已内置 Universal `libmimc_sdk.dylib`，包含 `x86_64` 和 `arm64`。

宿主启用 App Sandbox 时，需要网络客户端权限：

```xml
<key>com.apple.security.network.client</key>
<true/>
```

开发时可以临时指定 SDK 路径：

```bash
FLUTTER_MIMC_CPP_SDK_LIBRARY=/absolute/path/libmimc_sdk.dylib \
  flutter run -d macos
```

## Windows 和 Linux 配置

Windows/Linux 不内置小米 C++ SDK 二进制，需要在目标系统构建：

```bash
# Linux
tool/build_desktop_sdk.sh linux

# Windows Git Bash，需要先配置 VCPKG_ROOT
tool/build_desktop_sdk.sh windows
```

生成文件放置位置：

```text
linux/vendor/libmimc_sdk.so
windows/vendor/mimc_sdk.dll
```

相关非系统动态库也要放入对应的 `vendor` 目录，Flutter 构建时会一起打包。

## 生命周期

用户退出业务账号时，应注销并释放实例：

```dart
await subscription.cancel();
await mimc.logout();
await mimc.dispose();
```

切换业务用户后重新调用 `initialize()`，不要让不同用户共用同一个已初始化实例。

## 异常处理

```dart
try {
  await mimc.sendMessage(
    toAccount: '<RECIPIENT_ACCOUNT>',
    payload: utf8.encode('hello'),
  );
} on MimcException catch (error) {
  print('MIMC error: ${error.code} ${error.message}');
}
```

常见错误：

| code | 含义 |
|---|---|
| `not_initialized` | 尚未调用 `initialize()` |
| `invalid_token` | Token 为空或 JSON 无效 |
| `unsupported` | 当前平台不支持该功能 |
| `web_sdk_load_failed` | WebJS 静态资源加载失败 |
| `invalid_rts_*` | RTS 参数错误 |
| `native_*` | 桌面 C/C++ 桥返回错误 |

## 测试

```bash
flutter analyze
flutter test
tool/test_native_bridge.sh
```

运行示例：

```bash
cd example
flutter run
```

真实 E2E 测试需要通过环境变量提供测试 AppID、Token 接口和测试账号；仓库不包含
任何正式环境信息。

第三方 SDK 的固定提交和二进制 SHA-256 记录在 `THIRD_PARTY_SDKS.md`。

## 许可证

Apache License 2.0。
