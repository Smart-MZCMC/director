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
| **心跳保活** | 周期性续期控制权锁。**续期失败会提示「控制权已丢失」并清掉本地锁状态** |
| **采访状态栏** | 横向卡片展示各采访点状态（🟢就绪 / 🟡准备中 / 🔵未就绪 / 🔴离线） |
| **切台** | 滑动确认 → 下发「即将切台」；点「确认已切」→ 下发「正在播送」 |
| **内部通信** | 与包装端/解说端的消息面板 |
| **项目下拉** | 只列出当前账号有权访问的项目，按「正在直播 > 即将开始 > 无日程 > 已结束」排序 |
| **机位预设** | 由项目自己配置（管理后台可增删改），不再是代码里的 10 个固定名字 |

### 心跳失败为什么要说话

锁过期或被另一名导播抢走后，心跳接口返回「未持有控制权，需重新获取」。
如果把这个响应丢掉（1.3.0 及更早就是这么做的），导播会一直以为自己还持有
控制权、继续按切台键，而每次切台都被服务端拒绝——**现场表现为「按钮按了
没反应」**，是最难排查的一类故障。

### 机位预设取不到时怎么办

拉取失败或项目还没配机位时，回退到内置的 10 个名字。直播中需要的是一个
「大概能用」的按钮矩阵，不是一个空白页面。

## 配置

`lib/config.dart`：

```dart
class AppConfig {
  static const String serverUrl = 'http://zhdb.647382.xyz';
  static const String wsUrl = 'ws://zhdb.647382.xyz/ws';
}
```

导播端本来就要登录，所以不需要额外配置账号——它拿到的令牌同时用于 HTTP 与
WebSocket。

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
| `lock_update` | 控制权变更（服务端广播，`payload.reason` 为 `disconnect` 或 `timeout`） |
| `interview_status` | 采访点状态（服务端广播，含后端自动判定的 `offline`） |
| `system` | 系统提示；**连接成功的那条带 `current_shot`**，用于重连后恢复状态 |

断线采用指数退避重连（1s → 2s → 4s → 最大 10s）。重连后服务端的欢迎消息会把
项目当前的切台状态一并带回来，所以本端不必等下一次切台就能恢复显示。

> 通过校验的切台会写入后端的 `shot_cuts` 表，管理后台的「切台」弹窗据此给出
> 切台次数、平均停留时长与彩排/正式的分场统计。
