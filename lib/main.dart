import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';

/// 供 401 处理器跳转回登录页用。
///
/// 为什么用全局 navigatorKey 而不是让 ApiService 自己持有 Navigator：
/// 服务层不该知道界面的存在。回调式跳转是这里唯一合适的形态——
/// 请求是在 ApiService 内部发起的，那时拿不到任何 BuildContext。
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 恢复上一次的登录态必须在 runApp 之前完成：HomeScreen 一构造就会
  // 用 token 建 WebSocket，拿到空令牌等于匿名连接，
  // 而项目成员校验一开就会当场被 403 踢掉。
  final apiService = ApiService();
  final restoredUser = await apiService.restoreSession();

  runApp(MyApp(apiService: apiService, restoredUser: restoredUser));
}

class MyApp extends StatefulWidget {
  final ApiService apiService;

  /// 启动时恢复出来的账号；为空表示需要走登录页。
  final Map<String, dynamic>? restoredUser;

  const MyApp({
    super.key,
    required this.apiService,
    required this.restoredUser,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // 令牌过期时由 ApiService 触发。pushAndRemoveUntil 是必须的：
    // 不清栈的话返回键会退回已经失效的首页，导播会卡在「一直 401」的死循环里。
    widget.apiService.onUnauthorized = _backToLogin;
  }

  void _backToLogin() {
    if (!mounted) return;
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(apiService: widget.apiService),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.restoredUser;
    final token = widget.apiService.token;
    return MaterialApp(
      title: '导播控制系统',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.grey.shade900,
        colorScheme: const ColorScheme.dark(primary: Colors.blue),
      ),
      home: (user != null && token != null)
          ? HomeScreen(
              apiService: widget.apiService,
              token: token,
              user: user,
            )
          : LoginScreen(apiService: widget.apiService),
    );
  }
}
