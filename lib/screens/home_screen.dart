import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/slide_to_confirm.dart';
import '../widgets/interview_status_bar.dart';
import '../widgets/chat_panel.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final String token;
  final Map<String, dynamic> user;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.token,
    required this.user,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WebSocketService _wsService = WebSocketService();
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  List<Project> _projects = [];
  Project? _selectedProject;
  List<InterviewPoint> _interviewPoints = [];
  bool _hasLock = false;
  bool _isConnected = false;
  List<ChatMessage> _chatMessages = [];
  String? _nextShotPreview; // 即将播送的内容（点击预设按钮时设置）

  @override
  void initState() {
    super.initState();
    _initWebSocket();
    _loadProjects();
    _startLockHeartbeat();
  }

  void _initWebSocket() {
    _wsService.connectionStream.listen((connected) {
      setState(() => _isConnected = connected);
    });

    _wsService.messageStream.listen((msg) {
      final type = msg['type'];
      if (type == 'next_shot') {
        final payload = msg['payload'];
        setState(() => _nextShotPreview = payload['content'] ?? '');
      } else if (type == 'confirm_switch') {
        final payload = msg['payload'];
        setState(() => _nextShotPreview = null);
      } else if (type == 'chat') {
        final payload = msg['payload'];
        final senderId = msg['sender_id'];
        // 过滤自己发的消息（服务端会回传）
        if (senderId == widget.user['id']) return;
        setState(() {
          _chatMessages.add(ChatMessage(
            sender: '其他',
            content: payload['message'] ?? '',
            timestamp: DateTime.now(),
          ));
        });
        _scrollChatToBottom();
      } else if (type == 'interview_status') {
        final payload = msg['payload'];
        _updateInterviewFromWS(payload);
      } else if (type == 'lock_update') {
        _refreshLockStatus();
      }
    });
  }

  void _updateInterviewFromWS(Map<String, dynamic> payload) {
    final pointCode = payload['point_code'];
    final pointName = payload['point_name'] ?? pointCode;
    final status = payload['status'];
    setState(() {
      final idx = _interviewPoints.indexWhere((p) => p.pointCode == pointCode);
      if (idx >= 0) {
        _interviewPoints[idx] = InterviewPoint(
          id: _interviewPoints[idx].id,
          pointCode: pointCode,
          pointName: _interviewPoints[idx].pointName,
          status: status,
        );
      } else {
        // 采访点不在列表中，自动添加
        _interviewPoints.add(InterviewPoint(
          id: 0,
          pointCode: pointCode,
          pointName: pointName,
          status: status,
        ));
      }
    });
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await widget.apiService.getProjects();
      setState(() {
        _projects = projects;
        if (projects.isNotEmpty) {
          _selectedProject = projects.first;
          _onProjectChanged(projects.first);
        }
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _onProjectChanged(Project project) async {
    setState(() {
      _selectedProject = project;
      _nextShotPreview = null;
    });

    // 断开旧连接，用正确的 projectId 重新连接
    _wsService.disconnect();
    _wsService.connect(token: widget.token, projectId: project.id);

    try {
      final points = await widget.apiService.getInterviewStatuses(project.id);
      setState(() => _interviewPoints = points);
    } catch (e) {
      // ignore
    }

    _refreshLockStatus();
  }

  void _startLockHeartbeat() {
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (_hasLock && _selectedProject != null) {
        widget.apiService.heartbeat(_selectedProject!.id);
      }
    });
  }

  Future<void> _refreshLockStatus() async {
    if (_selectedProject == null) return;
    try {
      final status = await widget.apiService.getLockStatus(_selectedProject!.id);
      setState(() => _hasLock = status['locked'] == true && status['user_id'] == widget.user['id']);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _acquireLock() async {
    if (_selectedProject == null) return;
    try {
      final result = await widget.apiService.acquireLock(_selectedProject!.id);
      if (result['message'] != null) {
        setState(() => _hasLock = true);
        _showToast('已获取控制权');
      } else if (result['error'] != null) {
        _showToast(result['error']);
      }
    } catch (e) {
      _showToast('获取控制权失败');
    }
  }

  Future<void> _releaseLock() async {
    if (_selectedProject == null) return;
    try {
      await widget.apiService.releaseLock(_selectedProject!.id);
      setState(() => _hasLock = false);
      _showToast('已释放控制权');
    } catch (e) {
      _showToast('释放控制权失败');
    }
  }

  // 点击预设按钮：只设置"即将播送"预览，不发送 WS
  void _selectPreset(String label) {
    setState(() => _nextShotPreview = label);
  }

  // 滑动确认：将预览内容正式推送到"正在播送"
  void _onSlideConfirm(String content) {
    if (_selectedProject == null) return;
    _wsService.sendConfirmSwitch(_selectedProject!.id, content);
    setState(() => _nextShotPreview = null);
    _showToast('已推送: $content');
  }

  void _sendChatMessage() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || _selectedProject == null) return;
    _wsService.sendChat(_selectedProject!.id, text);
    // 本地立即显示（服务端回传会被过滤）
    setState(() {
      _chatMessages.add(ChatMessage(
        sender: '我',
        content: text,
        timestamp: DateTime.now(),
      ));
    });
    _chatInputController.clear();
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _wsService.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        backgroundColor: Colors.grey.shade800,
        title: Text(
          _selectedProject?.name ?? '导播端',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _isConnected ? '已连接' : '断开',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                widget.user['display_name'] ?? widget.user['username'] ?? '',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _hasLock
                ? TextButton.icon(
                    onPressed: _releaseLock,
                    icon: const Icon(Icons.lock_open, color: Colors.orange),
                    label: const Text('释放控制权', style: TextStyle(color: Colors.orange)),
                  )
                : TextButton.icon(
                    onPressed: _acquireLock,
                    icon: const Icon(Icons.lock, color: Colors.green),
                    label: const Text('获取控制权', style: TextStyle(color: Colors.green)),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 项目选择
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                const Text('项目: ', style: TextStyle(color: Colors.white70)),
                Expanded(
                  child: DropdownButton<Project>(
                    value: _selectedProject,
                    isExpanded: true,
                    dropdownColor: Colors.grey.shade800,
                    style: const TextStyle(color: Colors.white),
                    items: _projects.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.name),
                    )).toList(),
                    onChanged: (p) {
                      if (p != null) _onProjectChanged(p);
                    },
                  ),
                ),
              ],
            ),
          ),

          // 采访状态栏
          InterviewStatusBar(
            points: _interviewPoints,
            hasLock: _hasLock,
          ),

          // 预设按钮区域 + 滑动确认
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // 预设按钮网格
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2,
                      children: [
                        _presetButton('全景'),
                        _presetButton('50米'),
                        _presetButton('100米'),
                        _presetButton('1000米'),
                        _presetButton('20×50接力'),
                        _presetButton('跳远'),
                        _presetButton('跳高'),
                        _presetButton('跳长绳'),
                        _presetButton('韵律操'),
                        _presetButton('领导讲话'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 滑动确认：将选中的内容推送到"正在播送"
                  SlideToConfirm(
                    onConfirm: _onSlideConfirm,
                    preview: _nextShotPreview,
                  ),
                ],
              ),
            ),
          ),

          // 内部通信区
          Expanded(
            flex: 2,
            child: ChatPanel(
              messages: _chatMessages,
              inputController: _chatInputController,
              scrollController: _chatScrollController,
              onSend: _sendChatMessage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetButton(String label) {
    final isSelected = _nextShotPreview == label;
    return ElevatedButton(
      onPressed: _hasLock ? () => _selectPreset(label) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Colors.orange.shade700
            : (_hasLock ? Colors.blue.shade700 : Colors.grey.shade700),
        disabledBackgroundColor: Colors.grey.shade800,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _hasLock ? Colors.white : Colors.grey,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
