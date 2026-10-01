import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 上的 JWT 持久化：走 MainActivity 里自己写的 SharedPreferences。
///
/// 异常一律吞掉并退回内存行为。平台通道在单元测试（无 Activity）与
/// Windows 桌面端（无实现）都会抛 MissingPluginException，
/// 而这里抛出去只会让整个应用起不来——令牌丢了顶多重新登录一次。
class TokenStore {
  static const MethodChannel _channel =
      MethodChannel('smart_mzcmc/token_store');

  String? _fallback;

  Future<String?> read() async {
    final value = await _invoke<String>('read', null);
    if (value != null && value.isNotEmpty) return value;
    return _fallback;
  }

  Future<void> write(String token) async {
    _fallback = token;
    await _invoke<void>('write', token);
  }

  Future<void> clear() async {
    _fallback = null;
    await _invoke<void>('clear', null);
  }

  /// 非 Android 平台直接短路，不去惊动平台通道。
  Future<T?> _invoke<T>(String method, Object? argument) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<T>(method, argument);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[TokenStore] $method 失败: ${e.code} ${e.message}');
      return null;
    }
  }
}
