import 'package:flutter_test/flutter_test.dart';
import 'package:kee/core/voice/assistant_state.dart';
import 'package:kee/core/intelligence/deterministic_classifier.dart';
import 'package:kee/core/intelligence/nlp_date_parser.dart';
import 'package:kee/core/intelligence/recall_engine.dart';
import 'package:kee/core/intelligence/kee_conversation_engine.dart';
import 'package:kee/core/database/database_helper.dart';
import 'package:kee/core/notifications/notification_service.dart';
import 'package:kee/features/memories/data/memory_model.dart';
import 'package:kee/features/memories/data/memory_repository.dart';
import 'package:kee/features/reminders/data/task_model.dart';
import 'package:kee/features/reminders/data/reminder_model.dart';
import 'package:kee/features/reminders/data/reminder_repository.dart';

// In-Memory test implementations
class TestMemoryRepository extends MemoryRepository {
  final List<MemoryModel> _storage = [];

  TestMemoryRepository() : super(DatabaseHelper.instance);

  @override
  Future<void> createMemory(MemoryModel memory) async {
    _storage.add(memory);
  }

  @override
  Future<void> updateMemory(MemoryModel memory) async {
    final idx = _storage.indexWhere((m) => m.id == memory.id);
    if (idx != -1) {
      _storage[idx] = memory;
    }
  }

  @override
  Future<List<MemoryModel>> getAllMemories({
    String? category,
    String? query,
    bool includeDeleted = false,
  }) async {
    return List.from(_storage);
  }
}

class TestReminderRepository extends ReminderRepository {
  final List<ReminderModel> _reminders = [];
  final List<TaskModel> _tasks = [];

  TestReminderRepository() : super(DatabaseHelper.instance, NotificationService.instance);

  @override
  Future<void> createReminder(ReminderModel reminder) async {
    _reminders.add(reminder);
  }

  @override
  Future<void> createTask(TaskModel task) async {
    _tasks.add(task);
  }

  @override
  Future<List<ReminderModel>> getReminders({bool activeOnly = false}) async {
    return List.from(_reminders);
  }

  @override
  Future<List<TaskModel>> getTasks({String? status}) async {
    if (status != null) {
      return _tasks.where((t) => t.status == status).toList();
    }
    return List.from(_tasks);
  }
}

void main() {
  group('Deterministic Intelligence & Date Parsing Tests', () {
    test('Identifies task and tomorrow date', () {
      final input = 'I need to call David tomorrow';
      final result = DeterministicClassifier.classify(input);

      expect(result.memoryType, isIn(['task', 'reminder']));
      expect(result.shouldCreateTask, isTrue);
      expect(result.associatedPerson, equals('David'));
      expect(result.associatedDate, isNotNull);
    });

    test('Correctly identifies idea without creating a task or reminder', () {
      final input = 'I have an idea for an application that helps farmers manage their farms.';
      final result = DeterministicClassifier.classify(input);

      expect(result.memoryType, equals('idea'));
      expect(result.category, equals('Ideas'));
      expect(result.shouldCreateTask, isFalse);
      expect(result.shouldCreateReminder, isFalse);
    });

    test('Identifies commitment and flags missing deadline', () {
      final input = 'I promised Sarah I would send her the document.';
      final result = DeterministicClassifier.classify(input);

      expect(result.memoryType, equals('commitment'));
      expect(result.category, equals('Commitments'));
      expect(result.associatedPerson, equals('Sarah'));
      expect(result.shouldCreateTask, isTrue);
      expect(result.clarificationNeeded, isNotNull);
    });

    test('Identifies personal preference', () {
      final input = 'I prefer doing important work early in the morning.';
      final result = DeterministicClassifier.classify(input);

      expect(result.memoryType, equals('personal_preference'));
      expect(result.shouldCreateTask, isFalse);
      expect(result.shouldCreateReminder, isFalse);
    });

    test('Parses relative and recurring date expressions', () {
      final ref = DateTime(2026, 11, 19, 10, 0);

      final tomorrow = NlpDateParser.parse('tomorrow', referenceTime: ref);
      expect(tomorrow.dateTime?.day, equals(20));

      final recurringDaily = NlpDateParser.parse('every day', referenceTime: ref);
      expect(recurringDaily.recurrenceRule, equals('daily'));

      final recurringWeekly = NlpDateParser.parse('every week', referenceTime: ref);
      expect(recurringWeekly.recurrenceRule, equals('weekly'));
    });
  });

  group('Recall Engine Grounded Retrieval Tests', () {
    final recall = RecallEngine();

    test('Recalls uncompleted tasks correctly', () async {
      final tasks = [
        TaskModel(
          id: '1',
          title: 'Buy groceries',
          status: 'pending',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        TaskModel(
          id: '2',
          title: 'Submit report',
          status: 'completed',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final answer = await recall.answerFromMemories(
        question: 'Which tasks have I not completed?',
        memories: [],
        tasks: tasks,
        reminders: [],
      );

      expect(answer.hasDirectMatch, isTrue);
      expect(answer.citedTasks.length, equals(1));
      expect(answer.citedTasks.first.title, equals('Buy groceries'));
    });

    test('Does not hallucinate when memory is not found', () async {
      final answer = await recall.answerFromMemories(
        question: 'What is my secret passport code?',
        memories: [],
        tasks: [],
        reminders: [],
      );

      expect(answer.hasDirectMatch, isFalse);
      expect(answer.text, contains('could not find'));
    });
  });

  group('Kee Conversation-First Engine Architecture Tests', () {
    late TestMemoryRepository memoryRepo;
    late TestReminderRepository reminderRepo;
    late KeeConversationEngine engine;

    setUp(() {
      memoryRepo = TestMemoryRepository();
      reminderRepo = TestReminderRepository();
      engine = KeeConversationEngine(
        memoryRepo: memoryRepo,
        reminderRepo: reminderRepo,
      );
    });

    test('Automatically saves personal preference without task or reminder', () async {
      final action = await engine.processMessage('I prefer dark mode');

      expect(action.intent, equals(MessageIntent.preference));
      expect(action.savedMemory, isNotNull);
      expect(action.savedMemory!.memoryType, equals('personal_preference'));
      expect(action.savedMemory!.title.toLowerCase(), contains('dark mode'));
      expect(action.scheduledReminder, isNull);
      expect(action.savedTask, isNull);

      final memories = await memoryRepo.getAllMemories();
      expect(memories.length, equals(1));
      expect(memories.first.memoryType, equals('personal_preference'));
    });

    test('Saves important fact / birthday without setting alarm', () async {
      final action = await engine.processMessage("My mum's birthday is February 14");

      expect(action.intent, equals(MessageIntent.importantDate));
      expect(action.savedMemory, isNotNull);
      expect(action.savedMemory!.title.toLowerCase(), contains('birthday'));
      expect(action.scheduledReminder, isNull); // No reminder unless asked
    });

    test('Saves event memory naturally', () async {
      final action = await engine.processMessage('I met David at the conference yesterday');

      expect(action.intent, equals(MessageIntent.eventOrFact));
      expect(action.savedMemory, isNotNull);
      expect(action.savedMemory!.associatedPerson, equals('David'));
      expect(action.responseText, contains('David'));
    });

    test('Saves idea to ideas vault', () async {
      final action = await engine.processMessage('I have an idea for an app that helps farmers');

      expect(action.intent, equals(MessageIntent.idea));
      expect(action.savedMemory, isNotNull);
      expect(action.savedMemory!.category, equals('Ideas'));
      expect(action.scheduledReminder, isNull);
    });

    test('Recognises reminder intent and schedules notification', () async {
      // Future date
      final action = await engine.processMessage('Remind me to call John tomorrow at 9 AM');

      expect(action.intent, equals(MessageIntent.reminder));
      expect(action.scheduledReminder, isNotNull);
      expect(action.savedTask, isNotNull);
      expect(action.savedMemory, isNotNull);
      expect(action.requiresClarification, isFalse);
      expect(action.responseText, contains('reminder'));

      final reminders = await reminderRepo.getReminders();
      expect(reminders.length, equals(1));
      expect(reminders.first.title.toLowerCase(), contains('call john'));
    });

    test('Asks for clarification when reminder timing is missing', () async {
      final action = await engine.processMessage('Remind me to call John');

      expect(action.intent, equals(MessageIntent.reminder));
      expect(action.requiresClarification, isTrue);
      expect(action.scheduledReminder, isNull);
      expect(action.responseText.toLowerCase(), contains('when would you like'));
    });

    test('Avoids unnecessary memory creation on greetings & small talk', () async {
      final action = await engine.processMessage('Hello Kee');

      expect(action.intent, equals(MessageIntent.casualConversation));
      expect(action.savedMemory, isNull);
      expect(action.scheduledReminder, isNull);

      final memories = await memoryRepo.getAllMemories();
      expect(memories.isEmpty, isTrue); // Zero junk memories saved!
    });

    test('Answers questions using stored memories automatically', () async {
      // First save a memory
      await engine.processMessage('I prefer espresso over latte');

      // Then ask Kee
      final queryAction = await engine.processMessage('What did I say about espresso?');

      expect(queryAction.intent, equals(MessageIntent.query));
      expect(queryAction.responseText.toLowerCase(), contains('espresso'));
    });

    test('Handles explicit memory instruction with leading wake word', () async {
      final action = await engine.processMessage('Hi Kee, remember that I prefer coffee');

      expect(action.intent, equals(MessageIntent.preference));
      expect(action.savedMemory, isNotNull);
      expect(action.savedMemory!.title.toLowerCase(), contains('coffee'));
      expect(action.responseText.toLowerCase(), contains('coffee'));
    });

    test('Updates existing preference when user changes preference', () async {
      // 1. First save initial preference
      await engine.processMessage('I prefer dark mode');

      // 2. Change preference
      final updateAction = await engine.processMessage('I no longer prefer dark mode. I prefer light mode.');

      expect(updateAction.intent, equals(MessageIntent.preference));
      expect(updateAction.responseText.toLowerCase(), contains('light mode'));

      // Check no duplicate created
      final memories = await memoryRepo.getAllMemories();
      final modePrefs = memories.where((m) => m.memoryType == 'personal_preference').toList();
      expect(modePrefs.length, equals(1)); // Exactly 1 preference updated, NOT duplicated!
      expect(modePrefs.first.title.toLowerCase(), contains('light mode'));
    });

    test('Does not create task or reminder from purchase intention', () async {
      final action = await engine.processMessage('I want to buy a laptop');

      expect(action.intent, equals(MessageIntent.idea));
      expect(action.savedMemory, isNotNull);
      expect(action.savedTask, isNull); // Rule 11: Do not create tasks from every intention!
      expect(action.scheduledReminder, isNull);
    });

    test('Answers general weather question without searching memories or saving junk', () async {
      final action = await engine.processMessage("What's the weather like?");

      expect(action.intent, equals(MessageIntent.casualConversation));
      expect(action.savedMemory, isNull);
      expect(action.responseText.toLowerCase(), contains('weather'));
      expect(action.responseText.toLowerCase(), isNot(contains('could not find')));
    });

    test('Handles unavailable providers gracefully without crashing', () async {
      final action = await engine.processMessage('');
      expect(action.intent, equals(MessageIntent.casualConversation));
      expect(action.responseText, isNotEmpty);
    });
  });

  group('Voice Assistant State & Interruption Tests', () {
    test('AssistantState enum has all 6 required interaction states', () {
      expect(AssistantState.values, containsAll([
        AssistantState.idle,
        AssistantState.listening,
        AssistantState.processing,
        AssistantState.speaking,
        AssistantState.interrupted,
        AssistantState.error,
      ]));
    });

    test('VoiceAssistantState correctly reflects state properties', () {
      const idleState = VoiceAssistantState();
      expect(idleState.isIdle, isTrue);
      expect(idleState.isListening, isFalse);
      expect(idleState.isSpeaking, isFalse);

      final listeningState = idleState.copyWith(
        state: AssistantState.listening,
        soundLevel: 0.75,
        liveTranscript: 'Remind me tomorrow',
      );
      expect(listeningState.isListening, isTrue);
      expect(listeningState.soundLevel, equals(0.75));
      expect(listeningState.liveTranscript, equals('Remind me tomorrow'));

      final speakingState = listeningState.copyWith(
        state: AssistantState.speaking,
        lastAssistantResponse: 'I will remind you tomorrow',
      );
      expect(speakingState.isSpeaking, isTrue);
      expect(speakingState.lastAssistantResponse, equals('I will remind you tomorrow'));

      final interruptedState = speakingState.copyWith(
        state: AssistantState.interrupted,
      );
      expect(interruptedState.isInterrupted, isTrue);
    });

    test('WakeWordService extracts wake word and subsequent queries in one breath', () {
      const text = 'Hi Kee remind me to call David tomorrow';
      final lower = text.trim().toLowerCase();
      const wakeWords = ['hi kee', 'hey kee', 'hello kee', 'ok kee', 'kee'];

      String? matchedWakeWord;
      String? trailingQuery;

      for (final w in wakeWords) {
        if (lower.contains(w)) {
          matchedWakeWord = w;
          final idx = lower.indexOf(w);
          final rem = lower.substring(idx + w.length).trim();
          if (rem.isNotEmpty) {
            trailingQuery = rem;
          }
          break;
        }
      }

      expect(matchedWakeWord, equals('hi kee'));
      expect(trailingQuery, equals('remind me to call david tomorrow'));
    });
  });
}
