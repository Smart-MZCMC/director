import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/models.dart';

class ApiService {
  String? _token;

  void setToken(String token) => _token = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('${AppConfig.serverUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('登录失败: ${response.body}');
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
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> releaseLock(int projectId) async {
    final response = await http.post(
      Uri.parse('${AppConfig.serverUrl}/api/locks/$projectId/release'),
      headers: _headers,
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> heartbeat(int projectId) async {
    final response = await http.post(
      Uri.parse('${AppConfig.serverUrl}/api/locks/$projectId/heartbeat'),
      headers: _headers,
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getLockStatus(int projectId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.serverUrl}/api/locks/$projectId/status'),
      headers: _headers,
    );
    return jsonDecode(response.body);
  }
}
