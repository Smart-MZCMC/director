/// JWT 的本地持久化。
///
/// 为什么不用 shared_preferences：那个包会拖进 shared_preferences_android
/// 原生模块，在 Windows 上构建 APK 时会让 Kotlin 增量缓存崩掉
/// （Could not close incremental caches ... .tab），整个 assembleRelease 失败。
/// 这里的场景只存一个字符串，不值得为它换一个会打断构建的依赖，
/// 所以直接用 MainActivity 里的 SharedPreferences 走平台通道。
///
/// 平台通道只在 Android 上有实现；Windows 桌面端与单元测试落到 stub，
/// 表现为「只存在内存里」，也就是改动前的行为。
///
/// 选 stub 的条件写的是 `dart.library.html` 的反面历史：现在 Flutter Web
/// 走 js_interop，所以条件表达式里用的是 `dart.library.js_interop`。
library;

export 'token_store_stub.dart'
    if (dart.library.js_interop) 'token_store_web.dart'
    if (dart.library.io) 'token_store_native.dart';
