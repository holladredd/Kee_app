import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/memories/data/memory_model.dart';
import '../../features/reminders/data/reminder_model.dart';
import '../../features/reminders/data/task_model.dart';
import 'conversation_provider.dart';
import 'kee_conversation_engine.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final MessageIntent? intent;
  final MemoryModel? savedMemory;
  final ReminderModel? scheduledReminder;
  final TaskModel? savedTask;
  final List<MemoryModel> citations;
  final List<ReminderModel> citedReminders;
  final List<TaskModel> citedTasks;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.intent,
    this.savedMemory,
    this.scheduledReminder,
    this.savedTask,
    this.citations = const [],
    this.citedReminders = const [],
    this.citedTasks = const [],
  });
}

final unifiedChatProvider = NotifierProvider<UnifiedChatNotifier, List<ChatMessage>>(() {
  return UnifiedChatNotifier();
});

class UnifiedChatNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() {
    return [
      ChatMessage(
        text: 'Meet Kee, your Voice-First Knowledge Extension Entity. Talk naturally to capture what matters, set reminders, or recall anything you have entrusted to memory.\n\nYour memory. Extended.',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    ];
  }

  /// Sends a text message, processes it through Kee's intelligence engine,
  /// and automatically updates the single unified chat thread.
  Future<ConversationAction> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Message cannot be empty');
    }

    final userMessage = ChatMessage(
      text: trimmed,
      isUser: true,
      timestamp: DateTime.now(),
    );

    state = [...state, userMessage];

    try {
      final engine = ref.read(conversationEngineProvider);
      final action = await engine.processMessage(trimmed);

      final keeMessage = ChatMessage(
        text: action.responseText,
        isUser: false,
        timestamp: DateTime.now(),
        intent: action.intent,
        savedMemory: action.savedMemory,
        scheduledReminder: action.scheduledReminder,
        savedTask: action.savedTask,
        citations: action.citedMemories,
        citedReminders: action.citedReminders,
        citedTasks: action.citedTasks,
      );

      state = [...state, keeMessage];
      return action;
    } catch (e) {
      final errorMessage = ChatMessage(
        text: 'I encountered an issue processing that. Your local memory is intact—please try again.',
        isUser: false,
        timestamp: DateTime.now(),
      );
      state = [...state, errorMessage];
      rethrow;
    }
  }

  /// Records an exchange that happened via the voice orb / floating AI bubble
  /// so that it is instantly added to the single unified chat history.
  void recordVoiceTurn({
    required String userText,
    required String assistantText,
    MessageIntent? intent,
    MemoryModel? savedMemory,
    ReminderModel? scheduledReminder,
    TaskModel? savedTask,
    List<MemoryModel> citations = const [],
    List<ReminderModel> citedReminders = const [],
    List<TaskModel> citedTasks = const [],
  }) {
    final userMsg = ChatMessage(
      text: userText,
      isUser: true,
      timestamp: DateTime.now(),
    );
    final keeMsg = ChatMessage(
      text: assistantText,
      isUser: false,
      timestamp: DateTime.now(),
      intent: intent,
      savedMemory: savedMemory,
      scheduledReminder: scheduledReminder,
      savedTask: savedTask,
      citations: citations,
      citedReminders: citedReminders,
      citedTasks: citedTasks,
    );

    state = [...state, userMsg, keeMsg];
  }

  /// Clears the single conversation back to the clean greeting.
  void clearChat() {
    state = [
      ChatMessage(
        text: 'Conversation cleared. Say "Hi Kee", "What\'s up K", or tap to talk naturally.',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    ];
  }
}
