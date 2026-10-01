/// 运行期配置。
///
/// ⚠️ 这里是**编译期**常量：改完必须重新 `flutter build` 才能生效。
///    导播端是装在导播室机器上的原生应用，不像采访端（Web 产物，
///    可以直接改 public/interviewer/config.json）那样支持运行期覆盖。
///
/// serverUrl 指向反向代理入口（nginx 转发给 3000）。
/// wsUrl 走同一域名的 /ws（nginx 转给 3002）。
///
/// 已启用 HTTPS（Let's Encrypt 通配符证书），所以 wsUrl 用的是 wss://。
/// 这一点是硬约束而不是风格选择：页面/API 走 https 时，浏览器会把
/// ws:// 开头的连接按混合内容拦掉，且不报错——现场表现是「一直连不上」。
class AppConfig {
  static const String serverUrl = 'https://zhdb.647382.xyz';
  static const String wsUrl = 'wss://zhdb.647382.xyz/ws';
}
