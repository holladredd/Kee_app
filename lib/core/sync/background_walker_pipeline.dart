import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../database/database_tables.dart';
import '../intelligence/deterministic_classifier.dart';
import '../notifications/notification_service.dart';
import '../services/api_service.dart';

enum WalkerStatus { idle, walking, completed, error }

class BackgroundWalkerState {
  final WalkerStatus status;
  final DateTime? lastWalkedAt;
  final int syncedMutationsCount;
  final int pulledMemoriesCount;
  final int pulledTasksCount;
  final int pulledRemindersCount;
  final int consolidatedMemoriesCount;
  final int verifiedRemindersCount;
  final String? errorMessage;
  final bool isOnline;

  const BackgroundWalkerState({
    this.status = WalkerStatus.idle,
    this.lastWalkedAt,
    this.syncedMutationsCount = 0,
    this.pulledMemoriesCount = 0,
    this.pulledTasksCount = 0,
    this.pulledRemindersCount = 0,
    this.consolidatedMemoriesCount = 0,
    this.verifiedRemindersCount = 0,
    this.errorMessage,
    this.isOnline = true,
  });

  BackgroundWalkerState copyWith({
    WalkerStatus? status,
    DateTime? lastWalkedAt,
    int? syncedMutationsCount,
    int? pulledMemoriesCount,
    int? pulledTasksCount,
    int? pulledRemindersCount,
    int? consolidatedMemoriesCount,
    int? verifiedRemindersCount,
    String? errorMessage,
    bool? isOnline,
  }) {
    return BackgroundWalkerState(
      status: status ?? this.status,
      lastWalkedAt: lastWalkedAt ?? this.lastWalkedAt,
      syncedMutationsCount: syncedMutationsCount ?? this.syncedMutationsCount,
      pulledMemoriesCount: pulledMemoriesCount ?? this.pulledMemoriesCount,
      pulledTasksCount: pulledTasksCount ?? this.pulledTasksCount,
      pulledRemindersCount: pulledRemindersCount ?? this.pulledRemindersCount,
      consolidatedMemoriesCount: consolidatedMemoriesCount ?? this.consolidatedMemoriesCount,
      verifiedRemindersCount: verifiedRemindersCount ?? this.verifiedRemindersCount,
      errorMessage: errorMessage,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

final backgroundWalkerProvider =
    NotifierProvider<BackgroundWalkerPipeline, BackgroundWalkerState>(() {
  return BackgroundWalkerPipeline();
});

class BackgroundWalkerPipeline extends Notifier<BackgroundWalkerState> {
  static const String _lastSyncedKey = 'kee_last_synced_at';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Timer? _periodicTimer;
  bool _isWalking = false;

  @override
  BackgroundWalkerState build() {
    // Schedule background periodic walks (every 60 seconds)
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      walkNow();
    });

    // Run initial startup walk after short delay for DB readiness
    Future.delayed(const Duration(seconds: 3), () {
      walkNow();
    });

    ref.onDispose(() {
      _periodicTimer?.cancel();
    });

    return const BackgroundWalkerState();
  }

  /// Triggers a full run of the background walker pipeline across all stages:
  /// 1. Sync Queue Walker (push local mutations to backend & pull updates)
  /// 2. Reminder & Alarm Walker (verify offline notification alarms)
  /// 3. Memory Consolidation Walker (enrich raw memories with deterministic NLP)
  Future<void> walkNow({bool force = false}) async {
    if (_isWalking && !force) return;
    _isWalking = true;

    state = state.copyWith(status: WalkerStatus.walking, errorMessage: null);

    int pushedMutations = 0;
    int pulledMemories = 0;
    int pulledTasks = 0;
    int pulledReminders = 0;
    int verifiedReminders = 0;
    int consolidatedMemories = 0;
    bool online = true;

    try {
      final db = await DatabaseHelper.instance.database;

      // ─────────────────────────────────────────────────────────────
      // STAGE 1: Sync Queue Walker (Push & Pull)
      // ─────────────────────────────────────────────────────────────
      final syncResult = await _walkSyncQueue(db);
      pushedMutations = syncResult.pushedCount;
      pulledMemories = syncResult.pulledMemoriesCount;
      pulledTasks = syncResult.pulledTasksCount;
      pulledReminders = syncResult.pulledRemindersCount;
      online = syncResult.isOnline;

      // ─────────────────────────────────────────────────────────────
      // STAGE 2: Reminder & Notification Walker
      // ─────────────────────────────────────────────────────────────
      verifiedReminders = await _walkReminders(db);

      // ─────────────────────────────────────────────────────────────
      // STAGE 3: Memory Consolidation Walker
      // ─────────────────────────────────────────────────────────────
      consolidatedMemories = await _walkMemoryConsolidation(db);

      state = state.copyWith(
        status: WalkerStatus.completed,
        lastWalkedAt: DateTime.now(),
        syncedMutationsCount: pushedMutations,
        pulledMemoriesCount: pulledMemories,
        pulledTasksCount: pulledTasks,
        pulledRemindersCount: pulledReminders,
        verifiedRemindersCount: verifiedReminders,
        consolidatedMemoriesCount: consolidatedMemories,
        isOnline: online,
      );

      debugPrint(
        '[BackgroundWalkerPipeline] Walk completed successfully: '
        '$pushedMutations pushed, '
        '${pulledMemories + pulledTasks + pulledReminders} pulled, '
        '$verifiedReminders reminders verified, '
        '$consolidatedMemories memories consolidated.',
      );
    } catch (e) {
      debugPrint('[BackgroundWalkerPipeline] Walk error: $e');
      state = state.copyWith(
        status: WalkerStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      _isWalking = false;
    }
  }

  /// 1. Sync Queue Walker
  Future<_SyncWalkResult> _walkSyncQueue(Database db) async {
    final hasAuth = await ApiService.instance.hasToken();
    if (!hasAuth) {
      // User is offline or not logged in; local SQLite remains primary source of truth
      return const _SyncWalkResult(isOnline: false);
    }

    // Query pending sync queue mutations
    final queueRows = await db.query(
      DatabaseTables.tableSyncQueue,
      orderBy: 'created_at ASC',
      limit: 50,
    );

    String? lastSyncedAt;
    try {
      lastSyncedAt = await _storage.read(key: _lastSyncedKey);
    } catch (_) {}

    final List<Map<String, dynamic>> mutations = [];
    final List<int> processedQueueIds = [];

    for (final row in queueRows) {
      final id = row['id'] as int;
      final entityType = row['entity_type'] as String;
      final entityId = row['entity_id'] as String;
      final action = row['action'] as String;
      final createdAt = row['created_at'] as String;

      Map<String, dynamic> payload = {};

      if (action != 'delete') {
        if (entityType == 'memory') {
          final res = await db.query(
            DatabaseTables.tableMemories,
            where: 'id = ?',
            whereArgs: [entityId],
            limit: 1,
          );
          if (res.isNotEmpty) {
            final m = res.first;
            payload = {
              'title': m['title'],
              'original_content': m['original_content'],
              'processed_content': m['processed_content'],
              'memory_type': m['memory_type'],
              'category': m['category'],
              'tags': (m['tags'] as String?)?.split(',') ?? [],
              'is_pinned': m['is_pinned'] == 1,
            };
          }
        } else if (entityType == 'task') {
          final res = await db.query(
            DatabaseTables.tableTasks,
            where: 'id = ?',
            whereArgs: [entityId],
            limit: 1,
          );
          if (res.isNotEmpty) {
            final t = res.first;
            payload = {
              'title': t['title'],
              'description': t['description'],
              'status': t['status'],
              'due_date': t['due_date'],
              'due_time': t['due_time'],
            };
          }
        } else if (entityType == 'reminder') {
          final res = await db.query(
            DatabaseTables.tableReminders,
            where: 'id = ?',
            whereArgs: [entityId],
            limit: 1,
          );
          if (res.isNotEmpty) {
            final r = res.first;
            payload = {
              'title': r['title'],
              'scheduled_at': r['scheduled_at'],
              'timezone': r['timezone'],
              'is_enabled': r['is_enabled'] == 1,
            };
          }
        }
      }

      mutations.add({
        'entityType': entityType,
        'entityId': entityId,
        'action': action,
        'payload': payload,
        'clientTimestamp': createdAt,
      });

      processedQueueIds.add(id);
    }

    // Even if no mutations are queued, we can pull updates if we haven't synced recently
    if (mutations.isEmpty && lastSyncedAt != null) {
      final lastSyncDate = DateTime.tryParse(lastSyncedAt);
      if (lastSyncDate != null &&
          DateTime.now().difference(lastSyncDate).inMinutes < 2) {
        return const _SyncWalkResult(isOnline: true);
      }
    }

    final response = await ApiService.instance.post(
      '/sync',
      body: {
        if (lastSyncedAt != null) 'lastSyncedAt': lastSyncedAt,
        'mutations': mutations,
      },
    );

    if (!response.success || response.data == null) {
      return const _SyncWalkResult(isOnline: false);
    }

    final data = response.data as Map<String, dynamic>;

    // 1. Drain successfully sent queue items
    if (processedQueueIds.isNotEmpty) {
      final placeholders = List.filled(processedQueueIds.length, '?').join(',');
      await db.delete(
        DatabaseTables.tableSyncQueue,
        where: 'id IN ($placeholders)',
        whereArgs: processedQueueIds,
      );
    }

    // 2. Save server sync timestamp
    final serverTimestamp = data['serverTimestamp'] as String?;
    if (serverTimestamp != null) {
      await _storage.write(key: _lastSyncedKey, value: serverTimestamp);
    }

    // 3. Process pulled items from server
    int pulledMemories = 0;
    int pulledTasks = 0;
    int pulledReminders = 0;

    final pull = data['pull'] as Map<String, dynamic>?;
    if (pull != null) {
      // Upsert memories
      final serverMemories = pull['memories'] as List<dynamic>? ?? [];
      for (final item in serverMemories) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as String;
        final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM ${DatabaseTables.tableMemories} WHERE id = ?',
          [id],
        )) ?? 0;

        final tags = m['tags'] is List ? (m['tags'] as List).join(',') : (m['tags'] ?? '');
        final row = {
          'id': id,
          'title': m['title'] ?? 'Untitled Memory',
          'original_content': m['originalContent'] ?? m['original_content'] ?? '',
          'processed_content': m['processedContent'] ?? m['processed_content'],
          'memory_type': m['memoryType'] ?? m['memory_type'] ?? 'general_note',
          'category': m['category'] ?? 'General',
          'tags': tags,
          'is_pinned': (m['isPinned'] ?? m['is_pinned'] == true) ? 1 : 0,
          'created_at': m['createdAt'] ?? m['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': m['updatedAt'] ?? m['updated_at'] ?? DateTime.now().toIso8601String(),
          'deleted_at': m['deletedAt'] ?? m['deleted_at'],
          'sync_status': 'synced',
        };

        if (count > 0) {
          await db.update(DatabaseTables.tableMemories, row, where: 'id = ?', whereArgs: [id]);
        } else {
          await db.insert(DatabaseTables.tableMemories, row);
        }
        pulledMemories++;
      }

      // Upsert tasks
      final serverTasks = pull['tasks'] as List<dynamic>? ?? [];
      for (final item in serverTasks) {
        final t = item as Map<String, dynamic>;
        final id = t['id'] as String;
        final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM ${DatabaseTables.tableTasks} WHERE id = ?',
          [id],
        )) ?? 0;

        final row = {
          'id': id,
          'memory_id': t['memoryId'] ?? t['memory_id'],
          'title': t['title'] ?? 'Untitled Task',
          'description': t['description'],
          'priority': t['priority'] ?? 'normal',
          'status': t['status'] ?? 'pending',
          'due_date': t['dueDate'] ?? t['due_date'],
          'due_time': t['dueTime'] ?? t['due_time'],
          'created_at': t['createdAt'] ?? t['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': t['updatedAt'] ?? t['updated_at'] ?? DateTime.now().toIso8601String(),
          'sync_status': 'synced',
        };

        if (count > 0) {
          await db.update(DatabaseTables.tableTasks, row, where: 'id = ?', whereArgs: [id]);
        } else {
          await db.insert(DatabaseTables.tableTasks, row);
        }
        pulledTasks++;
      }

      // Upsert reminders
      final serverReminders = pull['reminders'] as List<dynamic>? ?? [];
      for (final item in serverReminders) {
        final r = item as Map<String, dynamic>;
        final id = r['id'] as String;
        final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM ${DatabaseTables.tableReminders} WHERE id = ?',
          [id],
        )) ?? 0;

        final notificationId = id.hashCode & 0x7FFFFFFF;
        final row = {
          'id': id,
          'task_id': r['taskId'] ?? r['task_id'],
          'memory_id': r['memoryId'] ?? r['memory_id'],
          'title': r['title'] ?? 'Untitled Reminder',
          'scheduled_at': r['scheduledAt'] ?? r['scheduled_at'] ?? DateTime.now().toIso8601String(),
          'timezone': r['timezone'] ?? 'UTC',
          'is_enabled': (r['isEnabled'] ?? r['is_enabled'] == true) ? 1 : 0,
          'notification_id': notificationId,
          'created_at': r['createdAt'] ?? r['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': r['updatedAt'] ?? r['updated_at'] ?? DateTime.now().toIso8601String(),
          'sync_status': 'synced',
        };

        if (count > 0) {
          await db.update(DatabaseTables.tableReminders, row, where: 'id = ?', whereArgs: [id]);
        } else {
          await db.insert(DatabaseTables.tableReminders, row);
        }
        pulledReminders++;
      }
    }

    return _SyncWalkResult(
      isOnline: true,
      pushedCount: processedQueueIds.length,
      pulledMemoriesCount: pulledMemories,
      pulledTasksCount: pulledTasks,
      pulledRemindersCount: pulledReminders,
    );
  }

  /// 2. Reminder & Alarm Walker
  Future<int> _walkReminders(Database db) async {
    int verifiedCount = 0;
    final now = DateTime.now();

    // Query active reminders scheduled in the future
    final activeReminders = await db.query(
      DatabaseTables.tableReminders,
      where: 'is_enabled = 1',
    );

    for (final r in activeReminders) {
      final id = r['id'] as String;
      final title = r['title'] as String;
      final scheduledAtStr = r['scheduled_at'] as String;
      final scheduledAt = DateTime.tryParse(scheduledAtStr);

      if (scheduledAt == null) continue;

      final notifId = r['notification_id'] as int? ?? (id.hashCode & 0x7FFFFFFF);

      if (scheduledAt.isAfter(now)) {
        // Ensure local offline notification is scheduled on device
        if (!kIsWeb) {
          await NotificationService.instance.scheduleReminder(
            notificationId: notifId,
            title: 'Kee: $title',
            body: 'Reminder scheduled for ${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}',
            scheduledDate: scheduledAt,
            payload: id,
          );
        }
        verifiedCount++;
      }
    }

    return verifiedCount;
  }

  /// 3. Memory Consolidation Walker
  Future<int> _walkMemoryConsolidation(Database db) async {
    int consolidatedCount = 0;

    // Find memories that haven't been indexed or consolidated by NLP
    final rawMemories = await db.query(
      DatabaseTables.tableMemories,
      where: 'processed_content IS NULL OR processed_content = ?',
      whereArgs: [''],
      limit: 25,
    );

    for (final m in rawMemories) {
      final id = m['id'] as String;
      final originalContent = m['original_content'] as String? ?? '';
      final title = m['title'] as String? ?? '';

      final textToClassify = title.isNotEmpty ? '$title. $originalContent' : originalContent;
      if (textToClassify.trim().isEmpty) continue;

      // Run deterministic offline classifier
      final classification = DeterministicClassifier.classify(textToClassify);

      final currentTags = m['tags'] as String? ?? '';
      final newTags = classification.tags.isNotEmpty
          ? classification.tags.join(',')
          : (currentTags.isNotEmpty ? currentTags : 'Note');

      await db.update(
        DatabaseTables.tableMemories,
        {
          'processed_content': classification.title,
          'category': classification.category,
          'memory_type': classification.memoryType,
          'tags': newTags,
          if (classification.associatedPerson != null)
            'associated_person': classification.associatedPerson,
          if (classification.associatedDate != null)
            'associated_date': classification.associatedDate!.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      consolidatedCount++;
    }

    return consolidatedCount;
  }
}

class _SyncWalkResult {
  final bool isOnline;
  final int pushedCount;
  final int pulledMemoriesCount;
  final int pulledTasksCount;
  final int pulledRemindersCount;

  const _SyncWalkResult({
    this.isOnline = true,
    this.pushedCount = 0,
    this.pulledMemoriesCount = 0,
    this.pulledTasksCount = 0,
    this.pulledRemindersCount = 0,
  });
}
