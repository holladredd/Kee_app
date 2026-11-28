import 'package:flutter_test/flutter_test.dart';
import 'package:kee/core/database/database_helper.dart';
import 'package:kee/core/intelligence/kee_conversation_engine.dart';
import 'package:kee/core/intelligence/recall_engine.dart';
import 'package:kee/core/notifications/notification_service.dart';
import 'package:kee/features/memories/data/memory_model.dart';
import 'package:kee/features/memories/data/memory_repository.dart';
import 'package:kee/features/reminders/data/reminder_model.dart';
import 'package:kee/features/reminders/data/reminder_repository.dart';
import 'package:kee/features/reminders/data/task_model.dart';

class _InMemoryRepo extends MemoryRepository {
  final List<MemoryModel> items = [];
  bool shouldFailWrites = false;

  _InMemoryRepo() : super(DatabaseHelper.instance);

  @override
  Future<void> createMemory(MemoryModel memory) async {
    if (shouldFailWrites) {
      throw Exception('Simulated SQLite write error');
    }
    items.add(memory);
  }

  @override
  Future<void> updateMemory(MemoryModel memory) async {
    if (shouldFailWrites) {
      throw Exception('Simulated SQLite update error');
    }
    final idx = items.indexWhere((m) => m.id == memory.id);
    if (idx != -1) {
      items[idx] = memory;
    }
  }

  @override
  Future<void> deleteMemory(String id, {bool hardDelete = false}) async {
    if (shouldFailWrites) {
      throw Exception('Simulated SQLite delete error');
    }
    items.removeWhere((m) => m.id == id);
  }

  @override
  Future<List<MemoryModel>> getAllMemories({
    String? category,
    String? query,
    bool includeDeleted = false,
  }) async => List.from(items);
}

class _InMemoryReminderRepo extends ReminderRepository {
  _InMemoryReminderRepo()
    : super(DatabaseHelper.instance, NotificationService.instance);

  @override
  Future<List<ReminderModel>> getReminders({bool activeOnly = false}) async =>
      [];

  @override
  Future<List<TaskModel>> getTasks({String? status}) async => [];
}

void main() {
  group('Memory Intent Recognition & Honest Persistence Tests', () {
    late _InMemoryRepo memoryRepo;
    late KeeConversationEngine engine;

    setUp(() {
      memoryRepo = _InMemoryRepo();
      engine = KeeConversationEngine(
        memoryRepo: memoryRepo,
        reminderRepo: _InMemoryReminderRepo(),
        notificationService: NotificationService.instance,
        recallEngine: RecallEngine(),
      );
    });

    test('saves "Please remember that I prefer morning meetings."', () async {
      final res = await engine.processMessage(
        'Please remember that I prefer morning meetings.',
      );
      expect(res.savedMemory, isNotNull);
      expect(memoryRepo.items.length, equals(1));
    });

    test(
      'saves "Can you remember my office is on the second floor?"',
      () async {
        final res = await engine.processMessage(
          'Can you remember my office is on the second floor?',
        );
        expect(res.savedMemory, isNotNull);
        expect(memoryRepo.items.length, equals(1));
      },
    );

    test('saves "Save that my car is parked on level 3."', () async {
      final res = await engine.processMessage(
        'Save that my car is parked on level 3.',
      );
      expect(res.savedMemory, isNotNull);
      expect(memoryRepo.items.length, equals(1));
    });

    test('saves "Note that I graduated in 2024."', () async {
      final res = await engine.processMessage('Note that I graduated in 2024.');
      expect(res.savedMemory, isNotNull);
      expect(memoryRepo.items.length, equals(1));
    });

    test(
      'polite question containing a save request is classified as a save',
      () async {
        final res = await engine.processMessage(
          'Can you remember my gate code is 4512?',
        );
        expect(res.intent, isNot(equals(MessageIntent.query)));
        expect(res.savedMemory, isNotNull);
        expect(memoryRepo.items.length, equals(1));
      },
    );

    test('ordinary small talk is not saved automatically', () async {
      final res = await engine.processMessage(
        'I am feeling pretty tired today after walking around.',
      );
      expect(res.savedMemory, isNull);
      expect(memoryRepo.items, isEmpty);
    });

    test(
      'passwords, PINs and authentication credentials are not automatically stored',
      () async {
        final r1 = await engine.processMessage(
          'Remember my password is secret123',
        );
        final r2 = await engine.processMessage('My PIN is 4829');
        final r3 = await engine.processMessage(
          'Save my 2FA authentication code 991234',
        );

        expect(r1.savedMemory, isNull);
        expect(r2.savedMemory, isNull);
        expect(r3.savedMemory, isNull);
        expect(memoryRepo.items, isEmpty);
      },
    );

    test(
      'successful save is confirmed only after repository success',
      () async {
        final res = await engine.processMessage(
          'Save that my office is on the second floor.',
        );
        expect(res.savedMemory, isNotNull);
        expect(memoryRepo.items.length, equals(1));
        expect(
          res.responseText.toLowerCase(),
          anyOf(contains('remembered'), contains('saved')),
        );
      },
    );

    test('failed saves do not produce false confirmation', () async {
      memoryRepo.shouldFailWrites = true;
      final res = await engine.processMessage(
        'Save that my car is parked on level 3.',
      );
      expect(res.savedMemory, isNull);
      expect(memoryRepo.items, isEmpty);
      expect(res.responseText.toLowerCase(), contains("couldn't save"));
    });

    test('forget intent requires confirmation before deleting', () async {
      await engine.processMessage('Save that my car is parked on level 3.');
      expect(memoryRepo.items.length, equals(1));

      final askConfirm = await engine.processMessage('Forget my car');
      expect(askConfirm.requiresClarification, isTrue);
      expect(memoryRepo.items.length, equals(1));

      final confirmed = await engine.processMessage('yes');
      expect(confirmed.responseText.toLowerCase(), contains('forgotten'));
      expect(memoryRepo.items, isEmpty);
    });
  });
}
