import 'dart:convert';
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

class _TestMemoryRepo extends MemoryRepository {
  final List<MemoryModel> items = [];

  _TestMemoryRepo() : super(DatabaseHelper.instance);

  @override
  Future<void> createMemory(MemoryModel memory) async => items.add(memory);

  @override
  Future<List<MemoryModel>> getAllMemories({
    String? category,
    String? query,
    bool includeDeleted = false,
  }) async => List.from(items);
}

class _TestReminderRepo extends ReminderRepository {
  final List<ReminderModel> reminders = [];
  final List<TaskModel> tasks = [];

  _TestReminderRepo()
    : super(DatabaseHelper.instance, NotificationService.instance);

  @override
  Future<void> createReminder(ReminderModel reminder) async =>
      reminders.add(reminder);

  @override
  Future<void> createTask(TaskModel task) async => tasks.add(task);

  @override
  Future<List<ReminderModel>> getReminders({bool activeOnly = false}) async =>
      List.from(reminders);

  @override
  Future<List<TaskModel>> getTasks({String? status}) async => List.from(tasks);
}

void main() {
  group('Action Intent & Routing Pipeline Tests', () {
    late _TestMemoryRepo memoryRepo;
    late _TestReminderRepo reminderRepo;
    late List<(String, String)> dispatchedActions;
    late Future<Map<String, dynamic>> Function(String action, String target)?
    customHandler;
    late KeeConversationEngine engine;

    setUp(() {
      memoryRepo = _TestMemoryRepo();
      reminderRepo = _TestReminderRepo();
      dispatchedActions = [];
      customHandler = null;
      engine = KeeConversationEngine(
        memoryRepo: memoryRepo,
        reminderRepo: reminderRepo,
        notificationService: NotificationService.instance,
        recallEngine: RecallEngine(),
        deviceActionHandler: (action, target) async {
          dispatchedActions.add((action, target));
          if (customHandler != null) {
            return customHandler!(action, target);
          }
          if (action == 'closeApp') {
            return {
              'success': false,
              'supported': false,
              'message':
                  "I can't force-close WhatsApp because Android doesn't allow assistant apps to close other apps.",
            };
          }
          return {'success': true, 'message': 'Executed $action: $target'};
        },
      );
    });

    test(
      'open and close apps route to deviceAction without memory fallback',
      () async {
        final openRes = await engine.processMessage('Open WhatsApp');
        expect(openRes.intent, equals(MessageIntent.deviceAction));
        expect(dispatchedActions.last, equals(('openApp', 'WhatsApp')));

        final closeRes = await engine.processMessage('Close WhatsApp');
        expect(closeRes.intent, equals(MessageIntent.deviceAction));
        expect(closeRes.responseText, isNot(contains("didn't save that")));
        expect(
          closeRes.responseText.toLowerCase(),
          contains("can't force-close"),
        );
      },
    );

    test('make a call handles both missing target and named contact', () async {
      final askTarget = await engine.processMessage('Make a phone call');
      expect(askTarget.intent, equals(MessageIntent.deviceAction));
      expect(askTarget.requiresClarification, isTrue);
      expect(askTarget.responseText.toLowerCase(), contains('who'));

      final callJohn = await engine.processMessage('Can you call John?');
      expect(callJohn.intent, equals(MessageIntent.deviceAction));
      expect(dispatchedActions.last, equals(('callContact', 'John')));
    });

    test('open dialer and show recent calls route cleanly', () async {
      final dialer = await engine.processMessage('Open the dialer');
      expect(dialer.intent, equals(MessageIntent.deviceAction));
      expect(dispatchedActions.last.$1, equals('openDialer'));

      final recent = await engine.processMessage('Show my recent calls');
      expect(recent.intent, equals(MessageIntent.deviceAction));
      expect(dispatchedActions.last.$1, equals('recentCalls'));
    });

    test(
      'compose message, open messages, and WhatsApp message route cleanly',
      () async {
        final openMsgs = await engine.processMessage('Open my messages');
        expect(openMsgs.intent, equals(MessageIntent.deviceAction));
        expect(dispatchedActions.last.$1, equals('openMessages'));

        final sms = await engine.processMessage('Compose an SMS to Sarah');
        expect(sms.intent, equals(MessageIntent.deviceAction));
        expect(dispatchedActions.last.$1, equals('composeSms'));
        expect(
          jsonDecode(dispatchedActions.last.$2)['target'],
          equals('Sarah'),
        );

        final wa = await engine.processMessage(
          'Send a WhatsApp message to John',
        );
        expect(wa.intent, equals(MessageIntent.deviceAction));
        expect(dispatchedActions.last.$1, equals('whatsappMessage'));
      },
    );

    test('flashlight control parses on and off states', () async {
      final onRes = await engine.processMessage('Turn on the flashlight');
      expect(onRes.intent, equals(MessageIntent.deviceAction));
      expect(dispatchedActions.last.$1, equals('setFlashlight'));
      expect(jsonDecode(dispatchedActions.last.$2)['enabled'], isTrue);

      final offRes = await engine.processMessage('Turn off the flashlight');
      expect(offRes.intent, equals(MessageIntent.deviceAction));
      expect(jsonDecode(dispatchedActions.last.$2)['enabled'], isFalse);
    });

    test('set an alarm parses time or asks for clarification', () async {
      final missingTime = await engine.processMessage('Set an alarm');
      expect(missingTime.intent, equals(MessageIntent.deviceAction));
      expect(missingTime.requiresClarification, isTrue);

      final withTime = await engine.processMessage('Set an alarm for 7:30 AM');
      expect(withTime.intent, equals(MessageIntent.deviceAction));
      expect(dispatchedActions.last.$1, equals('setAlarm'));
      final payload = jsonDecode(dispatchedActions.last.$2) as Map;
      expect(payload['hour'], equals(7));
      expect(payload['minute'], equals(30));
    });

    test('volume adjustment and return home screen route cleanly', () async {
      final vol = await engine.processMessage('Turn the volume up');
      expect(vol.intent, equals(MessageIntent.deviceAction));
      expect(dispatchedActions.last.$1, equals('adjustVolume'));
      expect(jsonDecode(dispatchedActions.last.$2)['direction'], equals('up'));

      final home = await engine.processMessage('Return to the home screen');
      expect(home.intent, equals(MessageIntent.deviceAction));
      expect(dispatchedActions.last.$1, equals('goHome'));
    });

    test(
      'saves personal info and retrieves it without action interference',
      () async {
        final saved = await engine.processMessage(
          'Save that my car is parked on level 3.',
        );
        expect(saved.savedMemory, isNotNull);

        final recalled = await engine.processMessage('Where is my car parked?');
        expect(recalled.intent, equals(MessageIntent.query));
        expect(recalled.citedMemories, isNotEmpty);
      },
    );

    test(
      'creates reminder and handles ordinary conversation cleanly',
      () async {
        final rem = await engine.processMessage(
          'Remind me to call John tomorrow at 9 AM',
        );
        expect(rem.intent, equals(MessageIntent.reminder));
        expect(rem.scheduledReminder, isNotNull);

        final greeting = await engine.processMessage('Hello Kee');
        expect(greeting.intent, equals(MessageIntent.casualConversation));
        expect(greeting.savedMemory, isNull);
      },
    );

    test(
      'unsupported system commands never return memory-saving prompt',
      () async {
        final screenshot = await engine.processMessage('Take a screenshot');
        expect(screenshot.intent, equals(MessageIntent.deviceAction));
        expect(screenshot.responseText, isNot(contains("didn't save that")));

        final wifi = await engine.processMessage('Turn off Wi-Fi');
        expect(wifi.intent, equals(MessageIntent.deviceAction));
        expect(wifi.responseText, isNot(contains("didn't save that")));
      },
    );

    test(
      'missing permissions are surfaced accurately from native handler',
      () async {
        customHandler = (action, target) async => {
          'success': false,
          'message':
              'Please allow Contacts permission so I can look up John in your phone book, then ask me again.',
        };

        final res = await engine.processMessage('Call John');
        expect(res.intent, equals(MessageIntent.deviceAction));
        expect(res.responseText.toLowerCase(), contains('permission'));
        expect(res.savedMemory, isNull);
      },
    );
  });
}
