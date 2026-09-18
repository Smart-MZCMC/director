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

  Future<List<Project>> getProjects() async {
    final response = await http.get(
      Uri.parse('${AppConfig.serverUrl}/api/admin/projects'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.map((e) => Project.fromJson(e)).toList();
    }
    throw Exception('获取项目列表失败');
  }

  Future<List<InterviewPoint>> getInterviewStatuses(int projectId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.serverUrl}/api/interview/$projectId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
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
