import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'database_tables.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('kee_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return await databaseFactory.openDatabase(
        filePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _createDB,
        ),
      );
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute(DatabaseTables.createMemoriesTable);
    await db.execute(DatabaseTables.createTasksTable);
    await db.execute(DatabaseTables.createRemindersTable);
    await db.execute(DatabaseTables.createAttachmentsTable);
    await db.execute(DatabaseTables.createSyncQueueTable);

    for (final indexQuery in DatabaseTables.createIndices) {
      await db.execute(indexQuery);
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // Clear all data (for reset or fresh start)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(DatabaseTables.tableAttachments);
    await db.delete(DatabaseTables.tableReminders);
    await db.delete(DatabaseTables.tableTasks);
    await db.delete(DatabaseTables.tableMemories);
    await db.delete(DatabaseTables.tableSyncQueue);
  }
}
