class TaskModel {
  final String id;
  final String? memoryId;
  final String title;
  final String? description;
  final String priority; // low, normal, high, urgent
  final String status; // pending, completed, cancelled
  final DateTime? dueDate;
  final String? dueTime;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;

  TaskModel({
    required this.id,
    this.memoryId,
    required this.title,
    this.description,
    this.priority = 'normal',
    this.status = 'pending',
    this.dueDate,
    this.dueTime,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
  });

  bool get isCompleted => status == 'completed';

  TaskModel copyWith({
    String? id,
    String? memoryId,
    String? title,
    String? description,
    String? priority,
    String? status,
    DateTime? dueDate,
    String? dueTime,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return TaskModel(
      id: id ?? this.id,
      memoryId: memoryId ?? this.memoryId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'memory_id': memoryId,
      'title': title,
      'description': description,
      'priority': priority,
      'status': status,
      'due_date': dueDate?.toIso8601String(),
      'due_time': dueTime,
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      id: map['id'] as String,
      memoryId: map['memory_id'] as String?,
      title: map['title'] as String,
      description: map['description'] as String?,
      priority: map['priority'] as String? ?? 'normal',
      status: map['status'] as String? ?? 'pending',
      dueDate: map['due_date'] != null
          ? DateTime.tryParse(map['due_date'].toString())
          : null,
      dueTime: map['due_time'] as String?,
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'].toString())
          : null,
      createdAt: DateTime.parse(map['created_at'].toString()),
      updatedAt: DateTime.parse(map['updated_at'].toString()),
      syncStatus: map['sync_status'] as String? ?? 'pending',
    );
  }
}
