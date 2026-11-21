/// User model matching the backend auth response shape.
/// Backend returns: { id, email, createdAt, _count?: { memories, tasks, reminders } }
class UserModel {
  final String id;
  final String email;
  final DateTime createdAt;
  final int memoriesCount;
  final int tasksCount;
  final int remindersCount;

  const UserModel({
    required this.id,
    required this.email,
    required this.createdAt,
    this.memoriesCount = 0,
    this.tasksCount = 0,
    this.remindersCount = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final counts = json['_count'] as Map<String, dynamic>?;

    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      memoriesCount: counts?['memories'] as int? ?? 0,
      tasksCount: counts?['tasks'] as int? ?? 0,
      remindersCount: counts?['reminders'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    DateTime? createdAt,
    int? memoriesCount,
    int? tasksCount,
    int? remindersCount,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      memoriesCount: memoriesCount ?? this.memoriesCount,
      tasksCount: tasksCount ?? this.tasksCount,
      remindersCount: remindersCount ?? this.remindersCount,
    );
  }
}
