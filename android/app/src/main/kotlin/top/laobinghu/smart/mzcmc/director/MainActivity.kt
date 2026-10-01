package top.laobinghu.smart.mzcmc.director

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 导播端的 Android 宿主。
 *
 * 这里手写一个 SharedPreferences 通道，而不是引入 shared_preferences 插件：
 * 那个插件会带入 shared_preferences_android 原生模块，在 Windows 上交叉构建
 * 时会让 Kotlin 增量缓存崩掉（Could not close incremental caches ... .tab），
 * 而需求只是记住一个 JWT 字符串。
 *
 * 存的是应用私有目录下的明文，没有额外加密。令牌的有效期由后端 JWT_TTL
 * 控制（默认 60 分钟），过期后服务端会拒绝，客户端也会自己解析 exp 后丢弃，
 * 所以不存在「拿到一个长期有效的凭据」这一档风险。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "smart_mzcmc/token_store"
    private val prefsName = "mzcmc_auth"
    private val tokenKey = "jwt"

    private val prefs by lazy { getSharedPreferences(prefsName, Context.MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(prefs.getString(tokenKey, null))
                    "write" -> {
                        val token = call.argument<String>("token")
                        if (token.isNullOrEmpty()) {
                            result.error("bad_args", "token 为空", null)
                        } else {
                            prefs.edit().putString(tokenKey, token).apply()
                            result.success(null)
                        }
                    }
                    "clear" -> {
                        prefs.edit().remove(tokenKey).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
