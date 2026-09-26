# smart-mzcmc-director

导播端 —— 系统的操作核心。导播用它抢占控制权、推送「下一项」、确认已切、并与包装端/解说端内部通信。

**Flutter** 应用，面向 Windows 桌面（`flutter run -d windows`），也可构建 Android。

## 为什么需要「滑动确认」

直播现场手忙脚乱，误触一次切台指令就会造成播出事故。所以推送动作不用点按，而是底部大滑动条：

```
[ >>> 滑动以确认切台 >>> ]
```

滑动确认只是**预告**（即将切台）；真正把画面切过去之后还要点「确认已切」。
两步各下发一条 `shot_state`，每条都同时携带「当前播送」和「即将切台」，
接收端因此不需要自己推断正在播的是什么。

## 功能

| 功能 | 说明 |
| :--- | :--- |
| **登录** | JWT 登录，令牌本地保存 |
| **控制权互斥** | 同一项目同时只有一名导播能发令；可主动释放，另一位再请求 |
| **心跳保活** | 周期性续期控制权锁，超时自动释放并通知另一位导播 |
| **采访状态栏** | 横向卡片展示各采访点状态（🟢就绪 / 🟡准备中 / 🔵未就绪 / 🔴离线） |
| **切台** | 滑动确认 → 下发「即将切台」；点「确认已切」→ 下发「正在播送」 |
| **内部通信** | 与包装端/解说端的消息面板 |

## 配置

`lib/config.dart`：

```dart
class AppConfig {
  static const String serverUrl = 'http://zhdb.647382.xyz';
  static const String wsUrl = 'ws://zhdb.647382.xyz/ws';
}
```

::: warning 这是编译期常量，改完必须重新 `flutter build`
导播端是装在导播室机器上的原生应用，没有可改的外部配置文件。
解说端、包装端、采访端都可以运行期改配置，只有导播端不行。
:::

| 场景 | `serverUrl` | `wsUrl` |
| :--- | :--- | :--- |
| 本地直连 | `http://<服务器IP>:3000` | `ws://<服务器IP>:3002/ws` |
| 反向代理（生产） | `http://<域名>` | `ws://<域名>/ws` |
| 反代 + HTTPS | `https://<域名>` | `wss://<域名>/ws` |

反代形态下 nginx 会把 `/ws` 转到 3002，所以客户端不需要知道 3002 这个端口。
当前线上用的是反代 + HTTP，所以是 `http://` / `ws://`。

## 开发与构建

需要 **Flutter ≥ 3.44.0**（`pubspec.lock` 的约束）。

```bash
flutter pub get
flutter run -d windows
flutter analyze
flutter test

flutter build windows --release   # 产物在 build/windows/x64/runner/Release/
```

## 目录

```
lib/
├── config.dart                     # 服务器地址
├── main.dart
├── models/models.dart
├── screens/
│   ├── login_screen.dart           # JWT 登录
│   └── home_screen.dart            # 主界面：控制权、推送、状态栏
├── services/
│   ├── api_service.dart            # HTTP：登录、锁的抢占/释放/心跳
│   └── websocket_service.dart      # WebSocket：收发指令与状态
└── widgets/
    ├── slide_to_confirm.dart       # 滑动确认控件
    ├── interview_status_bar.dart   # 采访状态卡片
    └── chat_panel.dart             # 内部通信面板
```

## 通信

发送的消息类型（统一协议，见后端 README）：

| type | 用途 |
| :--- | :--- |
| `shot_state` | 切台状态。滑动确认时 `{current: 旧机位, next: 新机位}`；点「确认已切」时 `{current: 新机位, next: ""}` |
| `chat` | 内部消息 / 心跳（心跳后端不落库、不转发、不计入统计） |
| `lock_update` | 控制权变更（服务端广播） |
| `interview_status` | 采访点状态（服务端广播） |

断线采用指数退避重连（1s → 2s → 4s → 最大 10s）。
