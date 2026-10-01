/// 没有原生实现时的占位：只存在内存里，进程一结束就丢。
///
/// 覆盖两种场景——单元测试（不该碰平台通道）与 Windows 桌面端
/// （没有 MainActivity 那套 SharedPreferences 实现）。
class TokenStore {
  /// 见 token_store_native.dart 里的同名常量。
  ///
  /// 这个值出现在导播端（唯一平台是 Android）就说明条件导入选错了文件。
  static const String storageKind = 'stub';

  String? _token;

  Future<String?> read() async => _token;

  Future<void> write(String token) async => _token = token;

  Future<void> clear() async => _token = null;
}
