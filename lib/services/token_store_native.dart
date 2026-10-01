import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 上的 JWT 持久化：走 MainActivity 里自己写的 SharedPreferences。
///
/// 异常一律吞掉并退回内存行为。平台通道在单元测试（无 Activity）与 Windows
/// 桌面端（无实现）都会失败，而这里抛出去只会让整个应用起不来——令牌丢了
/// 顶多重新登录一次。
class TokenStore {
  /// 标识当前生效的是哪一个实现，供测试断言条件导入选对了文件。
  ///
  /// 条件导入选错文件（最典型的是落到 stub）是这类代码最难发现的故障：
  /// 类型对、编译过、analyze 干净，只有真机上「重启后又要求登录」才暴露。
  static const String storageKind = 'native';

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
    // 参数必须是 Map，不能直接传 String。
    //
    // Kotlin 端读的是 call.argument<String>("token")，而 argument() 是
    // **从 Map 里按 key 取**。之前这里传的是裸 String，于是 call.arguments
    // 是个 String、没有 "token" 这个 key，取出来恒为 null，MainActivity
    // 每次都回 bad_args —— 令牌一个字都没存进 SharedPreferences。
    //
    // 症状特别有欺骗性：类型对、编译过、Kotlin 那边也只有一条 PlatformException，
    // 被这里 catch 掉只打了行日志，于是表现为「功能写了但完全不生效」，
    // 要到真机重启后才发现。参数形状用 mock channel 测死，见 test/token_store_test.dart。
    await _invoke<void>('write', {'token': token});
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
    } catch (e) {
      // 必须兜住「一切」异常，而不只是上面两种。实测 invokeMethod 在
      // ServicesBinding 尚未就绪时抛的是 FlutterError（不是 PlatformException），
      // 会让调用链直接崩掉——而丢一个令牌的后果只是重新登录一次，
      // 让整个应用起不来完全不成比例。
      debugPrint('[TokenStore] $method 异常，退回内存存储: $e');
      return null;
    }
  }
}