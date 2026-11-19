import 'package:flutter_test/flutter_test.dart';
import 'package:kee/core/intelligence/deterministic_classifier.dart';
import 'package:kee/core/intelligence/nlp_date_parser.dart';
import 'package:kee/core/intelligence/recall_engine.dart';
import 'package:kee/features/memories/data/memory_model.dart';
import 'package:kee/features/reminders/data/task_model.dart';
import 'package:kee/features/reminders/data/reminder_model.dart';

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
      expect(answer.text, contains('could not find any saved memories'));
    });
  });
}
