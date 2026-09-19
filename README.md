# smart-mzcmc-director

导播端 —— 系统的操作核心。导播用它抢占控制权、推送「下一项」、确认已切、并与包装端/解说端内部通信。

**Flutter** 应用，面向 Windows 桌面（`flutter run -d windows`），也可构建 Android。

## 为什么需要「滑动确认」

直播现场手忙脚乱，误触一次切台指令就会造成播出事故。所以推送动作不用点按，而是底部大滑动条：

```
[ >>> 滑动以确认推送 >>> ]
```

推送后留有几秒撤回窗口；如果上一条「下一项」还没被消费，新推送会自动覆盖它。

## 功能

| 功能 | 说明 |
| :--- | :--- |
| **登录** | JWT 登录，令牌本地保存 |
| **控制权互斥** | 同一项目同时只有一名导播能发令；可主动释放，另一位再请求 |
| **心跳保活** | 周期性续期控制权锁，超时自动释放并通知另一位导播 |
| **采访状态栏** | 横向卡片展示各采访点状态（🟢就绪 / 🟡准备中 / 🔵未就绪 / 🔴离线） |
| **推送下一项** | 滑动确认后广播 `next_shot`；点「确认已切」发 `confirm_switch` |
| **内部通信** | 与包装端/解说端的消息面板 |

## 配置

`lib/config.dart`：

```dart
class AppConfig {
  static const String serverUrl = 'http://127.0.0.1:3000';
  static const String wsUrl = 'ws://127.0.0.1:3002/ws';
}
```

部署前改成实际服务器地址。

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
| `next_shot` | 推送下一项（需滑动确认） |
| `confirm_switch` | 确认已切 |
| `chat` | 内部消息 / 心跳 |
| `lock_update` | 控制权变更（服务端广播） |
| `interview_status` | 采访点状态（服务端广播） |

断线采用指数退避重连（1s → 2s → 4s → 最大 10s），重连后状态型消息只取最新值。
