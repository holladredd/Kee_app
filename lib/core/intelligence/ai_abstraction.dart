import '../../features/memories/data/memory_model.dart';
import '../../features/reminders/data/task_model.dart';
import '../../features/reminders/data/reminder_model.dart';
import 'deterministic_classifier.dart';

abstract class AiAssistantEngine {
  /// Understands unstructured user capture and decomposes it into title, category, date, etc.
  Future<ClassificationResult> understandInput(String rawText);

  /// Classifies a memory into one of Kee's core information types
  Future<String> classifyMemory(String text);

  /// Extracts structured reminder/task details if present in the text
  Future<ClassificationResult> extractReminder(String text);

  /// Summarises multiple memories into a concise recap
  Future<String> summariseMemories(List<MemoryModel> memories);

  /// Retrieval-first Q&A: answers questions strictly from retrieved memories without hallucinating
  Future<RecallAnswer> answerFromMemories({
    required String question,
    required List<MemoryModel> memories,
    required List<TaskModel> tasks,
    required List<ReminderModel> reminders,
  });

  /// Status of the local engine (e.g. 'ready', 'not_loaded', 'unsupported')
  String get status;

  /// Human-readable engine name (e.g. 'Deterministic Rule Engine (Built-in)', 'On-Device GGUF Engine')
  String get name;
}

class RecallAnswer {
  final String text;
  final List<MemoryModel> citedMemories;
  final List<TaskModel> citedTasks;
  final List<ReminderModel> citedReminders;
  final bool hasDirectMatch;

  RecallAnswer({
    required this.text,
    this.citedMemories = const [],
    this.citedTasks = const [],
    this.citedReminders = const [],
    this.hasDirectMatch = true,
  });
}
