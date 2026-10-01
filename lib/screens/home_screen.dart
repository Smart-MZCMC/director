import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/slide_to_confirm.dart';
import '../widgets/interview_status_bar.dart';
import '../widgets/chat_panel.dart';
import '../widgets/version_banner.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final String token;
  final Map<String, dynamic> user;

  /// 可注入的 WebSocket 客户端，默认自己建一个。
  ///
  /// 留这个口子是为了 widget 测试：不替换掉的话 initState 会真的去连
  /// wss://zhdb.647382.xyz，让测试依赖网络、变慢，离线环境下直接失败。
  final WebSocketService? wsService;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.token,
    required this.user,
    this.wsService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // late：字段初始化器里不能访问 widget，必须延迟到 State 挂载之后。
  late final WebSocketService _wsService = widget.wsService ?? WebSocketService();
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  List<Project> _projects = [];
  Project? _selectedProject;
  List<InterviewPoint> _interviewPoints = [];
  bool _hasLock = false;
  bool _isConnected = false;
  final List<ChatMessage> _chatMessages = [];

  /// 机位预设按钮。来自后端按项目配置的列表，不再硬编码在 Dart 里。
  List<String> _presets = [];

  /// 控制权心跳定时器。必须留住引用：之前它是在 initState 里就地创建的
  /// Timer.periodic，没有字段也没有取消，页面销毁后仍在跑。
  Timer? _lockHeartbeatTimer;

  /// 当前正在播送的机位。每次切台都会连同 [_nextShotPreview] 一起上报给后端。
  String _currentPlaying = '';

  /// 预览中的机位（点预设按钮设置），滑动确认后即为「即将切台」。
  String? _nextShotPreview;

  /// 滑动确认是否已经发出「即将切台」。
  ///
  /// 只有在已预告、且尚未确认已切的情况下，「确认已切」按钮才可用——
  /// 否则会把同一个机位重复确认成正在播送。
  bool get _pendingConfirm =>
      _hasLock && _nextShotPreview != null && _nextShotPreview != _currentPlaying;


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
      if (type == 'shot_state') {
        // 后端把切台状态原样回给项目内其他角色；本端是发送方，
        // 自己的状态以本地为准，这里只用于兜底同步。
        final payload = msg['payload'] ?? const {};
        final current = (payload['current'] ?? '') as String;
        final next = (payload['next'] ?? '') as String;
        if (msg['sender_id'] == widget.user['id']) return;
        setState(() {
          _currentPlaying = current;
          _nextShotPreview = next.isEmpty ? null : next;
        });
      } else if (type == 'chat') {
        final payload = msg['payload'];
        final senderId = msg['sender_id'];
        // 过滤自己发的消息（服务端会回传）
        if (senderId == widget.user['id']) return;
        setState(() {
          _chatMessages.add(ChatMessage(
            // 发送者名由服务端盖章（sender_name），不在这里猜。
            // 老服务端不下发这个字段时退回角色名，至少比一律显示「其他」可辨认。
            sender: _resolveSenderName(msg),
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
      } else if (type == 'system') {
        _applyWelcomeState(msg['payload']);
      }
    });
  }

  /// 从广播消息里取出该显示的发送者名。
  ///
  /// 优先用服务端盖的 `sender_name`；它是登录账号的昵称/用户名，多端同场时
  /// 只有它能区分「谁在说话」。拿不到时退回 `sender_role` 的中文名，
  /// 再拿不到才显示「未知」——不要退回「其他」，那个词会把所有外来消息
  /// 重新糊成一片，等于没有发送者。
  String _resolveSenderName(Map<String, dynamic> msg) {
    final name = msg['sender_name'];
    if (name is String && name.isNotEmpty) return name;
    final role = msg['sender_role'];
    if (role is String && role.isNotEmpty) return _roleLabel(role);
    return '未知';
  }

  /// WS 角色标识的中文名。
  ///
  /// 与后端 app/ws/hub.go 的 roleLabel 保持同一套词表：老服务端还没开始
  /// 下发 sender_name 时，这是唯一能显示出发送者的信息。
  String _roleLabel(String role) {
    switch (role) {
      case 'director':
        return '导播';
      case 'commentator':
        return '解说';
      case 'packaging':
        return '包装';
      case 'interviewer':
        return '采访';
      case 'admin':
        return '管理员';
      case 'super_admin':
        return '超级管理员';
      default:
        return '未知';
    }
  }

  /// 渲染欢迎消息里带的当前切台状态。
  ///
  /// 后端在每次连接（含断线重连）时都会把 project_states 里的当前状态放进
  /// 第一条 system 消息。没有这一步的话，本端重连后会把自己清空成「未指定」，
  /// 直到下一次切台才恢复——而「下一次切台」可能还要等很久。
  void _applyWelcomeState(dynamic rawPayload) {
    if (rawPayload is! Map) return;
    if (rawPayload['state_available'] != true) return;
    final current = (rawPayload['current_shot'] ?? '') as String;
    final next = (rawPayload['next_shot'] ?? '') as String;
    if (!mounted) return;
    setState(() {
      _currentPlaying = current;
      _nextShotPreview = next.isEmpty ? null : next;
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
          // 取第一个。后端已按「正在直播 > 即将开始 > 无日程 > 已结束」排序，
          // 所以这不再是「ID 最小的那个」——那个规则没有任何时间含义，
          // 谁先建谁常驻，赛程换了还得手动去选。
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
      // 换项目意味着换一套切台状态，本地记录不再成立。
      _currentPlaying = '';
      _presets = [];
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

    await _loadCameras(project.id);
    _refreshLockStatus();
  }

  /// 拉取项目配置的机位预设。
  ///
  /// 失败时退回原来的 10 个名字而不是留一个空按钮区：导播在直播中需要的
  /// 是一个「大概能用」的按钮矩阵，不是一个空白页面。
  Future<void> _loadCameras(int projectId) async {
    List<String> names = [];
    try {
      final cameras = await widget.apiService.getCameras(projectId);
      names = cameras.map((c) => c.name).where((n) => n.isNotEmpty).toList();
    } catch (e) {
      // ignore
    }
    if (!mounted) return;
    setState(() {
      _presets = names.isNotEmpty ? names : _fallbackPresets;
    });
  }

  /// 取不到项目机位配置时的兜底按钮。与 B3 之前的硬编码列表一致，
  /// 这样即使后端还没升级，导播端也不会变成一个空界面。
  static const List<String> _fallbackPresets = [
    '全景',
    '50米',
    '100米',
    '1000米',
    '20×50接力',
    '跳远',
    '跳高',
    '跳长绳',
    '韵律操',
    '领导讲话',
  ];

  /// 控制权心跳。
  ///
  /// 响应**必须**检查：锁过期或被别的导播抢走后，后端会回
  /// 「未持有控制权，需重新获取」。此前这个返回值被直接丢掉，导播会一直
  /// 以为自己还持有控制权、继续按切台键，而每次切台都被服务端拒绝，
  /// 现场表现为「按钮按了没反应」。
  void _startLockHeartbeat() {
    _lockHeartbeatTimer?.cancel();
    _lockHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final project = _selectedProject;
      if (!_hasLock || project == null) return;

      try {
        final result = await widget.apiService.heartbeat(project.id);
        final error = result['error'];
        if (error == null) return;
        if (!mounted) return;
        setState(() => _hasLock = false);
        _showToast('控制权已丢失：$error');
      } catch (e) {
        // 网络抖动不该把人踢下线，等下一轮心跳或 lock_update 广播再说。
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

  // 点击预设按钮：只设置本地预览，不发 WS。
  // 真正下发要等滑动确认，避免误触。
  void _selectPreset(String label) {
    setState(() => _nextShotPreview = label);
  }

  /// 滑动确认：下发「即将切台」。
  ///
  /// 上报时把 [current] 一起带上——后端要求每次切台都给出完整的
  /// 「当前播送 + 即将切台」，接收端才能直接渲染而不必自己推断。
  /// 此时 [_currentPlaying] 不变，因为画面还没真的切过去。
  void _onSlideConfirm(String content) {
    if (_selectedProject == null) return;
    _wsService.sendShotState(
      _selectedProject!.id,
      current: _currentPlaying,
      next: content,
    );
    setState(() => _nextShotPreview = content);
    _showToast('即将切台: $content');
  }

  /// 确认已切：把预览中的机位提升为「当前播送」。
  ///
  /// 上报时 next 传空串，表示已经切完、没有待切项；后端据此让
  /// 解说端在「正在播送」和「即将播送」之间切换。
  void _onConfirmSwitched() {
    final target = _nextShotPreview;
    if (_selectedProject == null || target == null || target.isEmpty) return;
    _wsService.sendShotState(
      _selectedProject!.id,
      current: target,
      next: '',
    );
    setState(() {
      _currentPlaying = target;
      _nextShotPreview = null;
    });
    _showToast('正在播送: $target');
  }

  void _sendChatMessage() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || _selectedProject == null) return;
    _wsService.sendChat(_selectedProject!.id, text);
    // 本地立即显示（服务端回传会被过滤）
    setState(() {
      _chatMessages.add(ChatMessage(
        sender: widget.user['display_name'] ?? widget.user['username'] ?? '我',
        content: text,
        timestamp: DateTime.now(),
        isMine: true,
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
    _lockHeartbeatTimer?.cancel();
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
      // 按可用宽度选布局，不再让平板去拉伸手机竖屏布局。
      //
      // 之前只有一种布局，横向空间全给了聊天区，预设按钮网格被压成三列窄条，
      // 分镜按钮点不准；同时固定高度控件（状态条 + 滑动确认 + 确认按钮 ≈ 164px）
      // 在窗口高度低于约 500 时还会溢出 22px，控件被裁掉一半。
      //
      // 宽屏改成左右两栏：左栏是主操作流程（预设 + 切台确认），右栏是聊天。
      // 每栏都拿到完整高度，上面那个溢出也随之消失。
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_isWideLayout(constraints.maxWidth)) {
            return _buildWideLayout();
          }
          return _buildNarrowLayout();
        },
      ),
    );
  }

  /// 宽到足以并排显示两栏。
  ///
  /// 阈值取 720：低于它时两栏会各自窄到难以点击。手机横屏常见宽度是
  /// 640~900，所以横屏手机也会走两栏；竖屏手机（< 500）保持单栏。
  static bool _isWideLayout(double width) => width >= 720;

  /// 左栏：预设按钮 + 切台确认。导播的主要操作都在这里。
  Widget _buildSwitchColumn({int gridColumns = 3}) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 预设按钮网格。机位列表来自项目配置（GET /api/projects/:id/cameras），
          // 取不到时用兜底列表，不再是硬编码。
          Expanded(
            child: GridView.count(
              crossAxisCount: gridColumns,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2,
              children: [for (final name in _presets) _presetButton(name)],
            ),
          ),
          const SizedBox(height: 8),
          // 当前播送 / 即将切台状态条
          _buildShotStateBar(),
          const SizedBox(height: 8),
          // 滑动确认：下发「即将切台」
          SlideToConfirm(
            onConfirm: _onSlideConfirm,
            preview: _nextShotPreview,
            enabled: _hasLock,
          ),
          // 没有待切机位时按钮为 null，不放进 children。
          // 用 null-aware 元素语法而不是 if + 空值检查，lint 也会认。
          ?_buildConfirmButton(),
        ],
      ),
    );
  }

  /// 「确认已切」按钮。
  ///
  /// 没有待切机位时不渲染：一个永远置灰、又占掉 52px 高度的按钮，在窄窗口下
  /// 正是把下面几个控件挤出可视范围的那一环。要切台时它本来就会出现在滑动确认
  /// 之后，不存在「需要它来提示可以切了」的场景。
  Widget? _buildConfirmButton() {
    if (!_pendingConfirm) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton.icon(
          onPressed: _onConfirmSwitched,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(
            '确认已切: $_nextShotPreview',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  /// 项目选择栏。
  ///
  /// 两种布局都要用它，所以单独抽出来。
  Widget _buildProjectSelector() {
    return Container(
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
              items: _projects
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          // 带上计划时间与状态：项目多了以后，光看名字分不清
                          // 哪一场是现在这个。后端已经把当前/下一场排在最前。
                          p.scheduleLabel.isEmpty
                              ? p.name
                              : '${p.name}  ·  ${p.scheduleLabel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (p) {
                if (p != null) _onProjectChanged(p);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 聊天栏。
  Widget _buildChatPanel() {
    return ChatPanel(
      messages: _chatMessages,
      inputController: _chatInputController,
      scrollController: _chatScrollController,
      onSend: _sendChatMessage,
    );
  }

  /// 宽屏：左切换、右聊天。
  Widget _buildWideLayout() {
    return Column(
      children: [
        VersionBanner(serverUrl: AppConfig.serverUrl),
        _buildProjectSelector(),
        InterviewStatusBar(points: _interviewPoints, hasLock: _hasLock),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左栏按 3:2 分给切换区与聊天区：切换区是主操作，且要放下
              // 网格 + 状态条 + 滑动确认三样，聊天只是辅助沟通。
              Expanded(flex: 3, child: _buildSwitchColumn(gridColumns: 4)),
              const VerticalDivider(width: 1, color: Colors.white12),
              Expanded(flex: 2, child: _buildChatPanel()),
            ],
          ),
        ),
      ],
    );
  }

  /// 窄屏（竖屏手机）：单栏纵向堆叠。
  Widget _buildNarrowLayout() {
    return Column(
      children: [
        // 版本提示放在最上面：低于最低适配版本时部分功能会异常，
        // 导播员该在动手之前就看到，而不是等到某个功能不管用才发现。
        VersionBanner(serverUrl: AppConfig.serverUrl),
        _buildProjectSelector(),
        InterviewStatusBar(points: _interviewPoints, hasLock: _hasLock),
        Expanded(flex: 3, child: _buildSwitchColumn()),
        Expanded(flex: 2, child: _buildChatPanel()),
      ],
    );
  }

  /// 当前播送 / 即将切台状态条。
  ///
  /// 与解说端保持同一套语义：有待切项时显示「即将切台」，
  /// 确认已切后回到「当前播送」，让导播一眼看清自己下发了什么。
  Widget _buildShotStateBar() {
    final pending = _nextShotPreview;
    final hasPending = pending != null && pending.isNotEmpty;
    final label = hasPending ? '即将切台' : '当前播送';
    final value = hasPending ? pending : (_currentPlaying.isEmpty ? '未指定' : _currentPlaying);
    final color = hasPending ? Colors.orange.shade800 : Colors.blueGrey.shade800;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
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
