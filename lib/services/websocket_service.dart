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

  void sendNextShot(int projectId, String content) {
    _send('next_shot', projectId, {'content': content});
  }

  void sendConfirmSwitch(int projectId, String content) {
    _send('confirm_switch', projectId, {'content': content});
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
