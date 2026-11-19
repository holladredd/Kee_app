class DatabaseTables {
  DatabaseTables._();

  static const String tableMemories = 'memories';
  static const String tableTasks = 'tasks';
  static const String tableReminders = 'reminders';
  static const String tableAttachments = 'attachments';
  static const String tableSyncQueue = 'sync_queue';

  static const String createMemoriesTable = '''
    CREATE TABLE $tableMemories (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      original_content TEXT NOT NULL,
      processed_content TEXT,
      memory_type TEXT NOT NULL DEFAULT 'general_note',
      category TEXT NOT NULL DEFAULT 'General',
      tags TEXT,
      associated_person TEXT,
      associated_date TEXT,
      is_pinned INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    );
  ''';

  static const String createTasksTable = '''
    CREATE TABLE $tableTasks (
      id TEXT PRIMARY KEY,
      memory_id TEXT,
      title TEXT NOT NULL,
      description TEXT,
      priority TEXT NOT NULL DEFAULT 'normal',
      status TEXT NOT NULL DEFAULT 'pending',
      due_date TEXT,
      due_time TEXT,
      completed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pending',
      FOREIGN KEY (memory_id) REFERENCES $tableMemories(id) ON DELETE SET NULL
    );
  ''';

  static const String createRemindersTable = '''
    CREATE TABLE $tableReminders (
      id TEXT PRIMARY KEY,
      task_id TEXT,
      memory_id TEXT,
      title TEXT NOT NULL,
      scheduled_at TEXT NOT NULL,
      timezone TEXT NOT NULL DEFAULT 'UTC',
      recurrence_rule TEXT,
      is_enabled INTEGER NOT NULL DEFAULT 1,
      notification_id INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pending',
      FOREIGN KEY (task_id) REFERENCES $tableTasks(id) ON DELETE CASCADE,
      FOREIGN KEY (memory_id) REFERENCES $tableMemories(id) ON DELETE SET NULL
    );
  ''';

  static const String createAttachmentsTable = '''
    CREATE TABLE $tableAttachments (
      id TEXT PRIMARY KEY,
      memory_id TEXT,
      task_id TEXT,
      file_name TEXT NOT NULL,
      file_type TEXT NOT NULL,
      file_size INTEGER,
      local_path TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (memory_id) REFERENCES $tableMemories(id) ON DELETE CASCADE,
      FOREIGN KEY (task_id) REFERENCES $tableTasks(id) ON DELETE CASCADE
    );
  ''';

  static const String createSyncQueueTable = '''
    CREATE TABLE $tableSyncQueue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      action TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
  ''';

  static const List<String> createIndices = [
    'CREATE INDEX idx_memories_type ON $tableMemories(memory_type);',
    'CREATE INDEX idx_memories_category ON $tableMemories(category);',
    'CREATE INDEX idx_memories_pinned ON $tableMemories(is_pinned);',
    'CREATE INDEX idx_memories_updated ON $tableMemories(updated_at);',
    'CREATE INDEX idx_tasks_status ON $tableTasks(status);',
    'CREATE INDEX idx_tasks_due ON $tableTasks(due_date);',
    'CREATE INDEX idx_reminders_scheduled ON $tableReminders(scheduled_at);',
    'CREATE INDEX idx_reminders_enabled ON $tableReminders(is_enabled);',
    'CREATE INDEX idx_sync_queue_created ON $tableSyncQueue(created_at);',
  ];
}
