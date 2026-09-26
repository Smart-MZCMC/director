/// 运行期配置。
///
/// ⚠️ 这里是**编译期**常量：改完必须重新 `flutter build` 才能生效。
///    导播端是装在导播室机器上的原生应用，不像采访端（Web 产物，
///    可以直接改 public/interviewer/config.json）那样支持运行期覆盖。
///
/// serverUrl 指向反向代理入口（nginx 转发给 3000）。
/// wsUrl 走同一域名的 /ws（nginx 转给 3002）。
///
/// 如果以后启用 HTTPS，wsUrl 必须改成 wss://，
/// 否则浏览器会按混合内容拦截且不报错。
class AppConfig {
  static const String serverUrl = 'http://zhdb.647382.xyz';
  static const String wsUrl = 'ws://zhdb.647382.xyz/ws';
}
