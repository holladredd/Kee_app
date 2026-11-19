import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kee/core/database/database_helper.dart';
import 'package:kee/core/database/database_tables.dart';
import 'memory_model.dart';

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  return MemoryRepository(DatabaseHelper.instance);
});

final memoriesStreamProvider = FutureProvider<List<MemoryModel>>((ref) async {
  final repo = ref.watch(memoryRepositoryProvider);
  return repo.getAllMemories();
});

class MemoryRepository {
  final DatabaseHelper _dbHelper;

  MemoryRepository(this._dbHelper);

  Future<void> createMemory(MemoryModel memory) async {
    final db = await _dbHelper.database;
    await db.insert(
      DatabaseTables.tableMemories,
      memory.toMap(),
    );

    // Queue for sync outbox
    await db.insert(DatabaseTables.tableSyncQueue, {
      'entity_type': 'memory',
      'entity_id': memory.id,
      'action': 'create',
      'payload': memory.title,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateMemory(MemoryModel memory) async {
    final db = await _dbHelper.database;
    final updated = memory.copyWith(updatedAt: DateTime.now());
    await db.update(
      DatabaseTables.tableMemories,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [memory.id],
    );

    await db.insert(DatabaseTables.tableSyncQueue, {
      'entity_type': 'memory',
      'entity_id': memory.id,
      'action': 'update',
      'payload': updated.title,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteMemory(String id, {bool hardDelete = false}) async {
    final db = await _dbHelper.database;
    if (hardDelete) {
      await db.delete(
        DatabaseTables.tableMemories,
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      // Soft deletion
      await db.update(
        DatabaseTables.tableMemories,
        {
          'deleted_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    await db.insert(DatabaseTables.tableSyncQueue, {
      'entity_type': 'memory',
      'entity_id': id,
      'action': 'delete',
      'payload': id,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> togglePin(String id, bool currentStatus) async {
    final db = await _dbHelper.database;
    await db.update(
      DatabaseTables.tableMemories,
      {
        'is_pinned': currentStatus ? 0 : 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<MemoryModel>> getAllMemories({
    String? category,
    String? query,
    bool includeDeleted = false,
  }) async {
    final db = await _dbHelper.database;

    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (!includeDeleted) {
      whereClauses.add('deleted_at IS NULL');
    }

    if (category != null && category.isNotEmpty && category != 'All') {
      whereClauses.add('category = ?');
      whereArgs.add(category);
    }

    if (query != null && query.trim().isNotEmpty) {
      whereClauses.add('(title LIKE ? OR original_content LIKE ? OR tags LIKE ?)');
      final term = '%${query.trim()}%';
      whereArgs.addAll([term, term, term]);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final results = await db.query(
      DatabaseTables.tableMemories,
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'is_pinned DESC, created_at DESC',
    );

    return results.map((e) => MemoryModel.fromMap(e)).toList();
  }

  Future<List<MemoryModel>> getPinnedMemories() async {
    final db = await _dbHelper.database;
    final results = await db.query(
      DatabaseTables.tableMemories,
      where: 'is_pinned = 1 AND deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return results.map((e) => MemoryModel.fromMap(e)).toList();
  }

  Future<List<MemoryModel>> getRecentMemories({int limit = 5}) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      DatabaseTables.tableMemories,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return results.map((e) => MemoryModel.fromMap(e)).toList();
  }

  Future<MemoryModel?> getMemoryById(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      DatabaseTables.tableMemories,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return MemoryModel.fromMap(results.first);
  }
}
