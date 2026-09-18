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

  Project({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      description: json['description'] ?? '',
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

  ChatMessage({
    required this.sender,
    required this.content,
    required this.timestamp,
  });
}
