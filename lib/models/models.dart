class User {
  final int id;
  final String username;
  final String displayName;
  final String role;

  User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      displayName: json['display_name'] ?? '',
      role: json['role'] ?? '',
    );
  }
}

class Project {
  final int id;
  final String name;
  final String code;
  final String description;

  /// 计划时间窗与状态。后端按时间排序把「当前/下一场」置顶，这里只负责
  /// 把它们显示出来，让导播在下拉框里一眼看出哪一场是现在这个。
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final String venue;
  final String status;
  final String mode;

  Project({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    this.scheduledStart,
    this.scheduledEnd,
    this.venue = '',
    this.status = '',
    this.mode = '',
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      description: json['description'] ?? '',
      scheduledStart: _parseTime(json['scheduled_start']),
      scheduledEnd: _parseTime(json['scheduled_end']),
      venue: json['venue'] ?? '',
      status: json['status'] ?? '',
      mode: json['mode'] ?? '',
    );
  }

  static DateTime? _parseTime(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  /// 下拉框里的附加说明。没有日程时返回空串，不显示一个「未定」占位。
  String get scheduleLabel {
    final start = scheduledStart;
    if (start == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final text = '${two(start.month)}-${two(start.day)} '
        '${two(start.hour)}:${two(start.minute)}';
    switch (status) {
      case 'live':
        return '直播中 · $text';
      case 'finished':
        return '已结束 · $text';
      case 'cancelled':
        return '已取消 · $text';
      default:
        return text;
    }
  }
}

/// 机位预设。后端按 sort_order 排好序，这里不再自己排。
class ProjectCamera {
  final int id;
  final String name;

  ProjectCamera({required this.id, required this.name});

  factory ProjectCamera.fromJson(Map<String, dynamic> json) {
    return ProjectCamera(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }
}

class InterviewPoint {
  final int id;
  final String pointCode;
  final String pointName;
  final String status;

  InterviewPoint({
    required this.id,
    required this.pointCode,
    required this.pointName,
    required this.status,
  });

  factory InterviewPoint.fromJson(Map<String, dynamic> json) {
    return InterviewPoint(
      id: json['id'] ?? 0,
      pointCode: json['point_code'] ?? '',
      pointName: json['point_name'] ?? '',
      status: json['status'] ?? 'offline',
    );
  }
}

class ChatMessage {
  final String sender;
  final String content;
  final DateTime timestamp;

  /// 是否是本机发的消息。
  ///
  /// 单独一个布尔量，而不是拿 `sender == '我'` 去比字符串：发送者名字
  /// 现在来自服务端的 sender_name（可能是「张三」，也可能恰好就叫「我」），
  /// 用文案当身份判据迟早会在某个人叫「我」时把他的消息染成蓝色。
  final bool isMine;

  ChatMessage({
    required this.sender,
    required this.content,
    required this.timestamp,
    this.isMine = false,
  });
}
