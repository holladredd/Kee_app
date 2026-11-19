class ReminderModel {
  final String id;
  final String? taskId;
  final String? memoryId;
  final String title;
  final DateTime scheduledAt;
  final String timezone;
  final String? recurrenceRule; // daily, weekly, monthly, yearly, custom:N_days
  final bool isEnabled;
  final int? notificationId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;

  ReminderModel({
    required this.id,
    this.taskId,
    this.memoryId,
    required this.title,
    required this.scheduledAt,
    this.timezone = 'UTC',
    this.recurrenceRule,
    this.isEnabled = true,
    this.notificationId,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
  });

  bool get isRecurring => recurrenceRule != null && recurrenceRule!.isNotEmpty;
  bool get isOverdue => scheduledAt.isBefore(DateTime.now()) && isEnabled;

  ReminderModel copyWith({
    String? id,
    String? taskId,
    String? memoryId,
    String? title,
    DateTime? scheduledAt,
    String? timezone,
    String? recurrenceRule,
    bool? isEnabled,
    int? notificationId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return ReminderModel(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      memoryId: memoryId ?? this.memoryId,
      title: title ?? this.title,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      timezone: timezone ?? this.timezone,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      isEnabled: isEnabled ?? this.isEnabled,
      notificationId: notificationId ?? this.notificationId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'memory_id': memoryId,
      'title': title,
      'scheduled_at': scheduledAt.toIso8601String(),
      'timezone': timezone,
      'recurrence_rule': recurrenceRule,
      'is_enabled': isEnabled ? 1 : 0,
      'notification_id': notificationId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory ReminderModel.fromMap(Map<String, dynamic> map) {
    return ReminderModel(
      id: map['id'] as String,
      taskId: map['task_id'] as String?,
      memoryId: map['memory_id'] as String?,
      title: map['title'] as String,
      scheduledAt: DateTime.parse(map['scheduled_at'].toString()),
      timezone: map['timezone'] as String? ?? 'UTC',
      recurrenceRule: map['recurrence_rule'] as String?,
      isEnabled: (map['is_enabled'] as int? ?? 1) == 1,
      notificationId: map['notification_id'] as int?,
      createdAt: DateTime.parse(map['created_at'].toString()),
      updatedAt: DateTime.parse(map['updated_at'].toString()),
      syncStatus: map['sync_status'] as String? ?? 'pending',
    );
  }
}
