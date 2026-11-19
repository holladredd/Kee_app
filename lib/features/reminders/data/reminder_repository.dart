import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_helper.dart';
import '../../core/database/database_tables.dart';
import '../../core/notifications/notification_service.dart';
import 'task_model.dart';
import 'reminder_model.dart';

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ReminderRepository(DatabaseHelper.instance, NotificationService.instance);
});

final tasksStreamProvider = FutureProvider<List<TaskModel>>((ref) async {
  final repo = ref.watch(reminderRepositoryProvider);
  return repo.getTasks();
});

final remindersStreamProvider = FutureProvider<List<ReminderModel>>((ref) async {
  final repo = ref.watch(reminderRepositoryProvider);
  return repo.getReminders();
});

class ReminderRepository {
  final DatabaseHelper _dbHelper;
  final NotificationService _notificationService;

  ReminderRepository(this._dbHelper, this._notificationService);

  // ---------------- Tasks ----------------

  Future<void> createTask(TaskModel task) async {
    final db = await _dbHelper.database;
    await db.insert(
      DatabaseTables.tableTasks,
      task.toMap(),
    );

    await db.insert(DatabaseTables.tableSyncQueue, {
      'entity_type': 'task',
      'entity_id': task.id,
      'action': 'create',
      'payload': task.title,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateTask(TaskModel task) async {
    final db = await _dbHelper.database;
    final updated = task.copyWith(updatedAt: DateTime.now());
    await db.update(
      DatabaseTables.tableTasks,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );

    await db.insert(DatabaseTables.tableSyncQueue, {
      'entity_type': 'task',
      'entity_id': task.id,
      'action': 'update',
      'payload': updated.title,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> toggleTaskCompletion(String taskId, bool isCurrentlyCompleted) async {
    final db = await _dbHelper.database;
    final newStatus = isCurrentlyCompleted ? 'pending' : 'completed';
    final completedAt = isCurrentlyCompleted ? null : DateTime.now().toIso8601String();

    await db.update(
      DatabaseTables.tableTasks,
      {
        'status': newStatus,
        'completed_at': completedAt,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<List<TaskModel>> getTasks({String? status}) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      DatabaseTables.tableTasks,
      where: status != null ? 'status = ?' : null,
      whereArgs: status != null ? [status] : null,
      orderBy: 'created_at DESC',
    );
    return results.map((e) => TaskModel.fromMap(e)).toList();
  }

  Future<void> deleteTask(String taskId) async {
    final db = await _dbHelper.database;
    await db.delete(
      DatabaseTables.tableTasks,
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  // ---------------- Reminders ----------------

  Future<void> createReminder(ReminderModel reminder) async {
    final db = await _dbHelper.database;

    // Generate unique notification ID from hash of ID
    final notificationId = reminder.id.hashCode & 0x7FFFFFFF;
    final reminderWithNotifId = reminder.copyWith(notificationId: notificationId);

    await db.insert(
      DatabaseTables.tableReminders,
      reminderWithNotifId.toMap(),
    );

    // Schedule offline local notification
    if (reminder.isEnabled && reminder.scheduledAt.isAfter(DateTime.now())) {
      await _notificationService.scheduleReminder(
        notificationId: notificationId,
        title: 'Kee: ${reminder.title}',
        body: 'Scheduled reminder for ${reminder.scheduledAt.hour.toString().padLeft(2, '0')}:${reminder.scheduledAt.minute.toString().padLeft(2, '0')}',
        scheduledDate: reminder.scheduledAt,
        payload: reminder.id,
      );
    }

    await db.insert(DatabaseTables.tableSyncQueue, {
      'entity_type': 'reminder',
      'entity_id': reminder.id,
      'action': 'create',
      'payload': reminder.title,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateReminder(ReminderModel reminder) async {
    final db = await _dbHelper.database;
    final updated = reminder.copyWith(updatedAt: DateTime.now());

    await db.update(
      DatabaseTables.tableReminders,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );

    // Reschedule notification
    if (updated.notificationId != null) {
      await _notificationService.cancelReminder(updated.notificationId!);
      if (updated.isEnabled && updated.scheduledAt.isAfter(DateTime.now())) {
        await _notificationService.scheduleReminder(
          notificationId: updated.notificationId!,
          title: 'Kee: ${updated.title}',
          body: 'Scheduled reminder',
          scheduledDate: updated.scheduledAt,
          payload: updated.id,
        );
      }
    }
  }

  Future<void> snoozeReminder(String reminderId, Duration snoozeDuration) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      DatabaseTables.tableReminders,
      where: 'id = ?',
      whereArgs: [reminderId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      final reminder = ReminderModel.fromMap(results.first);
      final newScheduledAt = DateTime.now().add(snoozeDuration);
      await updateReminder(reminder.copyWith(scheduledAt: newScheduledAt));
    }
  }

  Future<void> toggleReminder(String reminderId, bool isEnabled) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseTables.tableReminders,
      {
        'is_enabled': isEnabled ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [reminderId],
    );

    final results = await db.query(
      DatabaseTables.tableReminders,
      where: 'id = ?',
      whereArgs: [reminderId],
      limit: 1,
    );
    if (results.isNotEmpty) {
      final reminder = ReminderModel.fromMap(results.first);
      if (reminder.notificationId != null) {
        if (!isEnabled) {
          await _notificationService.cancelReminder(reminder.notificationId!);
        } else if (reminder.scheduledAt.isAfter(DateTime.now())) {
          await _notificationService.scheduleReminder(
            notificationId: reminder.notificationId!,
            title: 'Kee: ${reminder.title}',
            body: 'Scheduled reminder',
            scheduledDate: reminder.scheduledAt,
            payload: reminder.id,
          );
        }
      }
    }
  }

  Future<void> deleteReminder(String reminderId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      DatabaseTables.tableReminders,
      where: 'id = ?',
      whereArgs: [reminderId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      final reminder = ReminderModel.fromMap(results.first);
      if (reminder.notificationId != null) {
        await _notificationService.cancelReminder(reminder.notificationId!);
      }
    }

    await db.delete(
      DatabaseTables.tableReminders,
      where: 'id = ?',
      whereArgs: [reminderId],
    );
  }

  Future<List<ReminderModel>> getReminders() async {
    final db = await _dbHelper.database;
    final results = await db.query(
      DatabaseTables.tableReminders,
      orderBy: 'scheduled_at ASC',
    );
    return results.map((e) => ReminderModel.fromMap(e)).toList();
  }

  Future<List<ReminderModel>> getUpcomingReminders({int limit = 5}) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final results = await db.query(
      DatabaseTables.tableReminders,
      where: 'scheduled_at >= ? AND is_enabled = 1',
      whereArgs: [now],
      orderBy: 'scheduled_at ASC',
      limit: limit,
    );
    return results.map((e) => ReminderModel.fromMap(e)).toList();
  }

  Future<List<ReminderModel>> getOverdueReminders() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final results = await db.query(
      DatabaseTables.tableReminders,
      where: 'scheduled_at < ? AND is_enabled = 1',
      whereArgs: [now],
      orderBy: 'scheduled_at DESC',
    );
    return results.map((e) => ReminderModel.fromMap(e)).toList();
  }
}
