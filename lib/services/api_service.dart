import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import 'token_store.dart';

class ApiService {
  String? _token;
  final TokenStore _store = TokenStore();

  /// 令牌被服务端判为无效时触发，由上层负责回到登录页。
  ///
  /// 令牌现在会跨进程保留（见 token_store.dart），所以「服务端回 401」
  /// 从此是一条真的会走到的路径：后台放久了令牌过期，导播切回应用后
  /// 拿着旧令牌只会看到一片「获取项目列表失败 (HTTP 401)」，
  /// 界面上没有任何「请重新登录」的提示。
  void Function()? onUnauthorized;

  String? get token => _token;

  void setToken(String token) {
    _token = token;
    unawaited(_store.write(token));
  }

  /// 启动时尝试恢复上一次的登录态。
  ///
  /// 返回账号信息表示可以直接进首页，返回 null 表示需要重新登录。
  ///
  /// 恢复流程是「读本地令牌 → 调 /api/auth/profile 验一次」而不是
  /// 本地解析 JWT 的 exp：后者的 TTL 只有 60 分钟，解析出来也没用，
  /// 还得额外处理时钟偏移；更要紧的是它看不见 token_version——
  /// 管理员改了密码之后旧令牌在服务端已经作废，只有真发一次请求才知道。
  /// 顺带也把用户资料取回来了，不必再往本地存第二份。
  Future<Map<String, dynamic>?> restoreSession() async {
    final saved = await _store.read();
    if (saved == null || saved.isEmpty) return null;
    _token = saved;
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.serverUrl}/api/auth/profile'),
              headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) return decoded;
      }
      debugPrint('[Auth] 本地令牌已失效 (HTTP ${response.statusCode})，需重新登录');
    } catch (e) {
      // 网络不通不等于令牌无效，保留本地令牌让用户重试，
      // 只在明确拿到 401/404 时才清。
      debugPrint('[Auth] 校验本地令牌失败，沿用现有令牌: $e');
      return null;
    }
    await _store.clear();
    _token = null;
    return null;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// 响应鉴权失败时清掉本地令牌并通知上层。
  ///
  /// 抽取出来是因为每个接口都要判一次，而漏掉任何一处都会让「重新登录」
  /// 这件事静默失效——界面上只会看到一句没头没尾的 HTTP 401。
  void _rejectUnauthorized(http.Response response) {
    if (response.statusCode != 401) return;
    _token = null;
    unawaited(_store.clear());
    onUnauthorized?.call();
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('${AppConfig.serverUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    // 状态码必须带上：界面要靠它区分「账号密码不对」和「服务端出了别的问题」。
    // 少了它，所有失败都显示成同一个提示，排查方向会从一开始就错。
    throw Exception('登录失败 (HTTP ${response.statusCode}): ${response.body}');
  }

  /// 项目列表。
  ///
  /// 走 /api/projects 而不是 /api/admin/projects：后者挂在 RequireRole(admin)
  /// 之后，导播的令牌拿到的一律是 403，下拉框恒定是空的。新接口只返回
  /// 当前账号有权访问的项目，并且后端已按「当前/下一场优先」排好序。
  Future<List<Project>> getProjects() async {
    final response = await http.get(
      Uri.parse('${AppConfig.serverUrl}/api/projects'),
      headers: _headers,
    );
    _rejectUnauthorized(response);
    if (response.statusCode == 200) {
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return list.map((e) => Project.fromJson(e)).toList();
    }
    throw Exception('获取项目列表失败 (HTTP ${response.statusCode})');
  }

  /// 项目的机位预设。
  ///
  /// 这些按钮此前是硬编码在 Dart 里的 10 个名字，换个场地就得改代码重新
  /// 构建。现在由项目自己配置，后台可改。
  Future<List<ProjectCamera>> getCameras(int projectId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.serverUrl}/api/projects/$projectId/cameras'),
      headers: _headers,
    );
    _rejectUnauthorized(response);
    if (response.statusCode == 200) {
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return list.map((e) => ProjectCamera.fromJson(e)).toList();
    }
    throw Exception('获取机位预设失败 (HTTP ${response.statusCode})');
  }

  Future<List<InterviewPoint>> getInterviewStatuses(int projectId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.serverUrl}/api/interview/$projectId'),
      headers: _headers,
    );
    _rejectUnauthorized(response);
    if (response.statusCode == 200) {
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return list.map((e) => InterviewPoint.fromJson(e)).toList();
    }
    throw Exception('获取采访状态失败');
  }

  // 控制权管理
  Future<Map<String, dynamic>> acquireLock(int projectId) async {
    final response = await http.post(
      Uri.parse('${AppConfig.serverUrl}/api/locks/$projectId/acquire'),
      headers: _headers,
    );
    _rejectUnauthorized(response);
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> releaseLock(int projectId) async {
    final response = await http.post(
      Uri.parse('${AppConfig.serverUrl}/api/locks/$projectId/release'),
      headers: _headers,
    );
    _rejectUnauthorized(response);
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> heartbeat(int projectId) async {
    final response = await http.post(
      Uri.parse('${AppConfig.serverUrl}/api/locks/$projectId/heartbeat'),
      headers: _headers,
    );
    _rejectUnauthorized(response);
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getLockStatus(int projectId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.serverUrl}/api/locks/$projectId/status'),
      headers: _headers,
    );
    _rejectUnauthorized(response);
    return jsonDecode(response.body);
  }
}
