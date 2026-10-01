/// 没有原生实现时的占位：只存在内存里，进程一结束就丢。
///
/// 覆盖两种场景——单元测试（不该碰平台通道）与 Windows 桌面端
/// （没有 MainActivity 那套 SharedPreferences 实现）。
class TokenStore {
  String? _token;

  Future<String?> read() async => _token;

  Future<void> write(String token) async => _token = token;

  Future<void> clear() async => _token = null;
}
