import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/memories/data/memory_model.dart';
import '../../features/reminders/data/task_model.dart';
import '../../features/reminders/data/reminder_model.dart';
import 'ai_abstraction.dart';
import 'deterministic_classifier.dart';
import 'recall_engine.dart';

final aiEngineProvider = Provider<AiAssistantEngine>((ref) {
  return LocalAiRunner.instance;
});

class LocalAiRunner implements AiAssistantEngine {
  static final LocalAiRunner instance = LocalAiRunner._init();

  LocalAiRunner._init();

  final RecallEngine _fallbackEngine = RecallEngine();
  String _selectedEngine = 'deterministic'; // 'deterministic', 'local_llm'
  bool _isLocalModelLoaded = false;
  String _modelName = 'Deterministic Engine (Active)';

  @override
  String get name => _modelName;

  @override
  String get status => _isLocalModelLoaded ? 'loaded' : 'fallback_deterministic';

  bool get isLocalModelLoaded => _isLocalModelLoaded;
  String get selectedEngine => _selectedEngine;

  void configureEngine({required String engineType, bool isModelAvailable = false}) {
    _selectedEngine = engineType;
    _isLocalModelLoaded = isModelAvailable;
    if (engineType == 'local_llm' && isModelAvailable) {
      _modelName = 'On-Device GGUF Model (Active)';
    } else {
      _modelName = 'Deterministic Rule Engine (Built-in)';
    }
  }

  @override
  Future<ClassificationResult> understandInput(String rawText) async {
    // If a local GGUF/llama model is loaded, we can run local inference here.
    // Otherwise, we utilize the fast, deterministic rule engine (Layer 1).
    return _fallbackEngine.understandInput(rawText);
  }

  @override
  Future<String> classifyMemory(String text) async {
    return _fallbackEngine.classifyMemory(text);
  }

  @override
  Future<ClassificationResult> extractReminder(String text) async {
    return _fallbackEngine.extractReminder(text);
  }

  @override
  Future<String> summariseMemories(List<MemoryModel> memories) async {
    return _fallbackEngine.summariseMemories(memories);
  }

  @override
  Future<RecallAnswer> answerFromMemories({
    required String question,
    required List<MemoryModel> memories,
    required List<TaskModel> tasks,
    required List<ReminderModel> reminders,
  }) async {
    return _fallbackEngine.answerFromMemories(
      question: question,
      memories: memories,
      tasks: tasks,
      reminders: reminders,
    );
  }
}
