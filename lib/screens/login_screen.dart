import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  /// 与 MyApp 共用同一个实例。
  ///
  /// 刻意不自己 new 一个：令牌失效时 ApiService 会把界面打回这个页面，
  /// 如果这里换了个新实例，打回来的登录页拿不到旧令牌，
  /// 而旧实例上的 onUnauthorized 回调仍指向已经销毁的路由。
  final ApiService apiService;

  const LoginScreen({super.key, required this.apiService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final ApiService _apiService = widget.apiService;
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _apiService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      _apiService.setToken(result['token']);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            apiService: _apiService,
            token: result['token'],
            user: result['user'],
          ),
        ),
      );
    } catch (e) {
      // 不能再一律说「请检查用户名和密码」。
      //
      // 之前所有异常都走这一句话，于是网络问题（服务器地址写错、没网、
      // release 包缺 INTERNET 权限）也显示成「密码错误」——账号密码明明是对的，
      // 于是排查方向从一开始就错了。真实的 1.4.x 现场就是这样被带偏的：
      // debug 版能登录、release 版不行，真正原因是权限而不是口令。
      setState(() {
        _error = _describeError(e);
      });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  /// 把登录失败的原因分成「服务端拒绝」与「联系不上服务端」。
  ///
  /// 这两类要分开：前者是账号密码问题，改了就能登进去；后者是地址、网络或
  /// 客户端权限问题，改密码没有任何用处。把两者混成一句话只会让人往错的方向查。
  String _describeError(Object error) {
    final text = error.toString();
    // ApiService 在服务端明确拒绝时抛出带状态码的异常。
    final isCredentialIssue = text.contains('401') || text.contains('403');
    if (isCredentialIssue) return '登录失败，请检查用户名和密码';

    // 连不上：这类错误信息里通常带着 SocketException / ClientException /
    // TimeoutException，把它原文带出来才有排查价值。
    return '无法连接服务器（$text）。\n'
        '这通常不是账号密码问题，请检查服务器地址与网络连通性。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broadcast_on_home, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                '导播控制系统',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: '用户名',
                  prefixIcon: const Icon(Icons.person),
                  filled: true,
                  fillColor: Colors.grey.shade800,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock),
                  filled: true,
                  fillColor: Colors.grey.shade800,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('登录', style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
