import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _intentionalClose = false;
  int _reconnectAttempts = 0;
  String? _token;
  int? _projectId;

  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool get isConnected => _channel != null;

  void connect({required String token, required int projectId}) {
    _token = token;
    _projectId = projectId;
    _intentionalClose = false;
    _doConnect();
  }

  void _doConnect() {
    if (_token == null || _projectId == null) return;
    try {
      final wsUri = Uri.parse(
        '${AppConfig.wsUrl}?project_id=$_projectId&role=director&token=$_token',
      );
      _channel = WebSocketChannel.connect(wsUri);

      _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0;
          _connectionController.add(true);
          final msg = jsonDecode(data.toString());
          _messageController.add(msg);
        },
        onDone: () {
          _connectionController.add(false);
          if (!_intentionalClose) _scheduleReconnect();
        },
        onError: (error) {
          _connectionController.add(false);
          if (!_intentionalClose) _scheduleReconnect();
        },
      );

      _startHeartbeat();
    } catch (e) {
      _scheduleReconnect();
    }
  }

  /// 保活心跳。
  ///
  /// 后端在入库之前就会丢弃 heartbeat，所以它不会进 messages 表、
  /// 不会计入项目消息统计、也不会广播给其他端——纯粹用来维持连接。
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'chat',
          'project_id': _projectId,
          'payload': {'message': 'heartbeat'},
        }));
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delay = Duration(seconds: (1 * (1 << (_reconnectAttempts - 1))).clamp(1, 10));
    _reconnectTimer = Timer(delay, _doConnect);
  }

  /// 上报切台状态。
  ///
  /// 后端只认 `shot_state` 一种切台消息，每次都必须把「当前播送」和
  /// 「即将切台」一起带上，接收端不需要自己推断：
  ///  - [current] 当前正在播送的机位
  ///  - [next]    本次要切过去的机位；传空串表示已经切完、进入正在播送状态
  void sendShotState(int projectId, {required String current, required String next}) {
    _send('shot_state', projectId, {'current': current, 'next': next});
  }

  void sendChat(int projectId, String content) {
    _send('chat', projectId, {'message': content});
  }

  void _send(String type, int projectId, Map<String, dynamic> payload) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': type,
      'project_id': projectId,
      'payload': payload,
    }));
  }

  void disconnect() {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _messageController.close();
  }
}
