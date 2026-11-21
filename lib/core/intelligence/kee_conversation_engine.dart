import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../features/memories/data/memory_model.dart';
import '../../features/memories/data/memory_repository.dart';
import '../../features/reminders/data/task_model.dart';
import '../../features/reminders/data/reminder_model.dart';
import '../../features/reminders/data/reminder_repository.dart';
import '../notifications/notification_service.dart';
import 'deterministic_classifier.dart';
import 'nlp_date_parser.dart';
import 'recall_engine.dart';
import 'ai_abstraction.dart';

enum MessageIntent {
  query,
  reminder,
  preference,
  importantDate,
  eventOrFact,
  idea,
  shoppingOrTask,
  casualConversation,
}

class ConversationAction {
  final String responseText;
  final MessageIntent intent;
  final MemoryModel? savedMemory;
  final ReminderModel? scheduledReminder;
  final TaskModel? savedTask;
  final List<MemoryModel> citedMemories;
  final List<ReminderModel> citedReminders;
  final List<TaskModel> citedTasks;
  final bool requiresClarification;

  const ConversationAction({
    required this.responseText,
    required this.intent,
    this.savedMemory,
    this.scheduledReminder,
    this.savedTask,
    this.citedMemories = const [],
    this.citedReminders = const [],
    this.citedTasks = const [],
    this.requiresClarification = false,
  });
}

/// Central intelligence service for Kee's conversation-first architecture.
/// Directs natural language inputs to memory capture, reminder scheduling,
/// or grounded memory retrieval behind the scenes.
class KeeConversationEngine {
  final MemoryRepository _memoryRepo;
  final ReminderRepository _reminderRepo;
  final NotificationService _notificationService;
  final RecallEngine _recallEngine;
  final Uuid _uuid = const Uuid();

  KeeConversationEngine({
    required MemoryRepository memoryRepo,
    required ReminderRepository reminderRepo,
    NotificationService? notificationService,
    RecallEngine? recallEngine,
  })  : _memoryRepo = memoryRepo,
        _reminderRepo = reminderRepo,
        _notificationService = notificationService ?? NotificationService.instance,
        _recallEngine = recallEngine ?? RecallEngine();

  /// Process any natural-language user message.
  Future<ConversationAction> processMessage(String rawInput) async {
    final trimmed = rawInput.trim();
    final lower = trimmed.toLowerCase();

    if (trimmed.isEmpty) {
      return const ConversationAction(
        responseText: "I'm listening. Tell me something to remember or ask me anything you've saved.",
        intent: MessageIntent.casualConversation,
      );
    }

    // ─── 1. GREETINGS & CASUAL CONVERSATION (Do NOT save junk) ───
    if (_isCasualGreeting(lower)) {
      return ConversationAction(
        responseText: _generateGreetingResponse(lower),
        intent: MessageIntent.casualConversation,
      );
    }

    // ─── 2. QUERIES & RETRIEVAL INTENT ────────────────────────────
    // If user is asking a question about memories, tasks, reminders, or facts
    if (_isQueryIntent(lower)) {
      return await _handleQuery(trimmed);
    }

    // ─── 3. EXPLICIT REMINDER INTENT ──────────────────────────────
    // e.g. "Remind me to call John tomorrow at 9 AM"
    if (_isReminderIntent(lower)) {
      return await _handleReminder(trimmed);
    }

    // ─── 4. PERSONAL PREFERENCE INTENT ────────────────────────────
    // e.g. "I prefer dark mode", "I love Ethiopian coffee"
    if (_isPreferenceIntent(lower)) {
      return await _handlePreference(trimmed);
    }

    // ─── 5. IMPORTANT DATE / BIRTHDAY / FACT ──────────────────────
    // e.g. "My mum's birthday is February 14"
    if (_isImportantDateOrFact(lower)) {
      return await _handleImportantDateOrFact(trimmed);
    }

    // ─── 6. IDEA / BRAINSTORM ─────────────────────────────────────
    // e.g. "I have an idea for an app that helps farmers"
    if (_isIdeaIntent(lower)) {
      return await _handleIdea(trimmed);
    }

    // ─── 7. SHOPPING & INTENTIONS ─────────────────────────────────
    // e.g. "I need to buy a new laptop", "Pick up groceries"
    if (_isShoppingOrTaskIntent(lower)) {
      return await _handleShoppingOrTask(trimmed);
    }

    // ─── 8. EVENT OR GENERAL MEMORY (Default Catch-all) ───────────
    // e.g. "I met David at the conference yesterday"
    return await _handleEventOrGeneralMemory(trimmed);
  }

  // ─────────────────────────────────────────────────────────────
  // HANDLERS
  // ─────────────────────────────────────────────────────────────

  Future<ConversationAction> _handleQuery(String question) async {
    final memories = await _memoryRepo.getAllMemories();
    final tasks = await _reminderRepo.getTasks();
    final reminders = await _reminderRepo.getReminders();

    final RecallAnswer answer = await _recallEngine.answerFromMemories(
      question: question,
      memories: memories,
      tasks: tasks,
      reminders: reminders,
    );

    return ConversationAction(
      responseText: answer.text,
      intent: MessageIntent.query,
      citedMemories: answer.citedMemories,
      citedReminders: answer.citedReminders,
      citedTasks: answer.citedTasks,
    );
  }

  Future<ConversationAction> _handleReminder(String text) async {
    final dateResult = NlpDateParser.parse(text);
    final classification = DeterministicClassifier.classify(text);

    // If the reminder mentions an action but lacks a date or time, ask for clarification
    if (dateResult.dateTime == null) {
      final title = classification.title;
      return ConversationAction(
        responseText: "When would you like to be reminded about '$title'? (e.g. tomorrow at 9 AM, in 2 hours, or Friday at 3 PM)",
        intent: MessageIntent.reminder,
        requiresClarification: true,
      );
    }

    final scheduledDate = dateResult.dateTime!;
    final title = classification.title;
    final now = DateTime.now();

    if (scheduledDate.isBefore(now)) {
      return ConversationAction(
        responseText: "That time appears to be in the past (${DateFormat('MMM d, h:mm a').format(scheduledDate)}). When should I schedule it?",
        intent: MessageIntent.reminder,
        requiresClarification: true,
      );
    }

    final reminderId = _uuid.v4();
    final taskId = _uuid.v4();
    final memoryId = _uuid.v4();

    // 1. Save Reminder in SQLite
    final reminder = ReminderModel(
      id: reminderId,
      taskId: taskId,
      memoryId: memoryId,
      title: title,
      scheduledAt: scheduledDate,
      timezone: 'local',
      recurrenceRule: dateResult.recurrenceRule,
      isEnabled: true,
      createdAt: now,
      updatedAt: now,
    );
    await _reminderRepo.createReminder(reminder);

    // 2. Save underlying Task in SQLite
    final task = TaskModel(
      id: taskId,
      memoryId: memoryId,
      title: title,
      priority: 'high',
      dueDate: scheduledDate,
      dueTime: '${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
    );
    await _reminderRepo.createTask(task);

    // 3. Save Memory record for recall
    final memory = MemoryModel(
      id: memoryId,
      title: title,
      originalContent: text,
      processedContent: 'Reminder scheduled for ${DateFormat('EEEE, MMM d, yyyy @ h:mm a').format(scheduledDate)}',
      memoryType: 'reminder',
      category: classification.category,
      tags: ['reminder', ...classification.tags],
      associatedPerson: classification.associatedPerson,
      associatedDate: scheduledDate,
      createdAt: now,
      updatedAt: now,
    );
    await _memoryRepo.createMemory(memory);

    // 4. Schedule local notification on device
    final notificationId = scheduledDate.millisecondsSinceEpoch ~/ 1000 % 1000000;
    await _notificationService.scheduleReminder(
      notificationId: notificationId,
      title: 'Kee Reminder',
      body: title,
      scheduledDate: scheduledDate,
    );

    final timeStr = DateFormat('EEEE, MMM d @ h:mm a').format(scheduledDate);
    final recur = dateResult.recurrenceRule != null ? ' (recurring ${dateResult.recurrenceRule})' : '';

    return ConversationAction(
      responseText: "I've set a reminder for **$title** on **$timeStr**$recur. I'll notify you on your device when it's time.",
      intent: MessageIntent.reminder,
      savedMemory: memory,
      scheduledReminder: reminder,
      savedTask: task,
    );
  }

  Future<ConversationAction> _handlePreference(String text) async {
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();

    // Check for existing preference with similar title/content to prevent duplicates
    final existingMemories = await _memoryRepo.getAllMemories();
    MemoryModel? existing;
    for (final m in existingMemories) {
      if (m.memoryType == 'personal_preference' &&
          (m.title.toLowerCase() == classification.title.toLowerCase() ||
              m.originalContent.toLowerCase() == text.toLowerCase())) {
        existing = m;
        break;
      }
    }

    if (existing != null) {
      // Update existing preference
      final updated = existing.copyWith(
        originalContent: text,
        updatedAt: now,
      );
      await _memoryRepo.updateMemory(updated);
      return ConversationAction(
        responseText: "I've updated your preference for **${classification.title}**.",
        intent: MessageIntent.preference,
        savedMemory: updated,
      );
    }

    final memory = MemoryModel(
      id: _uuid.v4(),
      title: classification.title,
      originalContent: text,
      processedContent: 'User preference: ${classification.title}',
      memoryType: 'personal_preference',
      category: 'Personal',
      tags: ['preference', ...classification.tags],
      createdAt: now,
      updatedAt: now,
    );
    await _memoryRepo.createMemory(memory);

    return ConversationAction(
      responseText: "Got it. I've remembered your preference: **${classification.title}**.",
      intent: MessageIntent.preference,
      savedMemory: memory,
    );
  }

  Future<ConversationAction> _handleImportantDateOrFact(String text) async {
    final dateResult = NlpDateParser.parse(text);
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();

    final memory = MemoryModel(
      id: _uuid.v4(),
      title: classification.title,
      originalContent: text,
      processedContent: classification.associatedPerson != null
          ? 'Associated with ${classification.associatedPerson}'
          : null,
      memoryType: 'important_date',
      category: classification.category,
      tags: ['important_date', ...classification.tags],
      associatedPerson: classification.associatedPerson,
      associatedDate: dateResult.dateTime,
      createdAt: now,
      updatedAt: now,
    );
    await _memoryRepo.createMemory(memory);

    final personNotice = classification.associatedPerson != null
        ? " associated with ${classification.associatedPerson}"
        : "";
    final dateNotice = dateResult.dateTime != null
        ? " for ${DateFormat('MMMM d').format(dateResult.dateTime!)}"
        : "";

    return ConversationAction(
      responseText: "I've made a note of **${classification.title}**$personNotice$dateNotice. I'll have it ready whenever you ask.",
      intent: MessageIntent.importantDate,
      savedMemory: memory,
    );
  }

  Future<ConversationAction> _handleIdea(String text) async {
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();

    final memory = MemoryModel(
      id: _uuid.v4(),
      title: classification.title,
      originalContent: text,
      memoryType: 'idea',
      category: 'Ideas',
      tags: ['idea', ...classification.tags],
      createdAt: now,
      updatedAt: now,
    );
    await _memoryRepo.createMemory(memory);

    return ConversationAction(
      responseText: "Great idea! I've captured **${classification.title}** in your ideas vault. You can revisit it anytime.",
      intent: MessageIntent.idea,
      savedMemory: memory,
    );
  }

  Future<ConversationAction> _handleShoppingOrTask(String text) async {
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();
    final taskId = _uuid.v4();
    final memoryId = _uuid.v4();

    final memory = MemoryModel(
      id: memoryId,
      title: classification.title,
      originalContent: text,
      memoryType: classification.memoryType,
      category: classification.category,
      tags: classification.tags,
      createdAt: now,
      updatedAt: now,
    );
    await _memoryRepo.createMemory(memory);

    final task = TaskModel(
      id: taskId,
      memoryId: memoryId,
      title: classification.title,
      priority: 'normal',
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    await _reminderRepo.createTask(task);

    return ConversationAction(
      responseText: "I've saved **${classification.title}** to your commitments.",
      intent: MessageIntent.shoppingOrTask,
      savedMemory: memory,
      savedTask: task,
    );
  }

  Future<ConversationAction> _handleEventOrGeneralMemory(String text) async {
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();
    final memoryId = _uuid.v4();

    final memory = MemoryModel(
      id: memoryId,
      title: classification.title,
      originalContent: text,
      memoryType: classification.associatedDate != null ? 'event' : 'personal_memory',
      category: classification.category,
      tags: classification.tags,
      associatedPerson: classification.associatedPerson,
      associatedDate: classification.associatedDate,
      createdAt: now,
      updatedAt: now,
    );
    await _memoryRepo.createMemory(memory);

    return ConversationAction(
      responseText: "Noted. I've remembered this: **${classification.title}**.",
      intent: MessageIntent.eventOrFact,
      savedMemory: memory,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // INTENT RECOGNITION HELPERS
  // ─────────────────────────────────────────────────────────────

  bool _isCasualGreeting(String lower) {
    return RegExp(r'^(hi|hello|hey|good morning|good afternoon|good evening|howdy|sup|greetings)(\s+kee)?[\.!]?$').hasMatch(lower) ||
        lower == 'who are you' ||
        lower == 'who are you?' ||
        lower == 'what can you do' ||
        lower == 'what can you do?' ||
        lower == 'help' ||
        lower == 'thank you' ||
        lower == 'thanks';
  }

  String _generateGreetingResponse(String lower) {
    if (lower.contains('thank')) {
      return "You're welcome. I'm here whenever you need to remember, schedule, or recall anything.";
    }
    if (lower.contains('who are you') || lower.contains('what can you do') || lower.contains('help')) {
      return "I am Kee (Knowledge Extension Entity)—your personal AI memory assistant.\n\n"
          "You can simply talk to me:\n"
          "• Tell me things to remember: *'My mum's birthday is Feb 14'*, *'I prefer dark mode'*, *'I met David at the tech summit'*\n"
          "• Schedule reminders: *'Remind me to call John tomorrow at 9 AM'*\n"
          "• Ask questions: *'What did I say about David?'*, *'What do I have tomorrow?'*\n\n"
          "Everything is securely stored and processed right on your device. Your memory. Extended.";
    }
    return "Hello! I'm Kee, ready to extend your memory. What's on your mind today?";
  }

  bool _isQueryIntent(String lower) {
    return lower.endsWith('?') ||
        RegExp(r'\b(what|which|when|who|where|how|did i|have i|do i have|tell me|show me|find|search|recall|look up|any reminders|upcoming)\b').hasMatch(lower);
  }

  bool _isReminderIntent(String lower) {
    return RegExp(r"\b(remind me|don'?t forget|alert me|notify me|set a reminder)\b").hasMatch(lower);
  }

  bool _isPreferenceIntent(String lower) {
    return RegExp(r'\b(i prefer|my preference|i always like|i love|i hate|i dislike|my favorite|my favourite)\b').hasMatch(lower);
  }

  bool _isImportantDateOrFact(String lower) {
    return RegExp(r'\b(birthday|anniversary|warranty|renewal|contract ends|expires?|due date)\b').hasMatch(lower);
  }

  bool _isIdeaIntent(String lower) {
    return RegExp(r'\b(idea for|what if we|thought about making|concept for|brainstorm)\b').hasMatch(lower);
  }

  bool _isShoppingOrTaskIntent(String lower) {
    return RegExp(r'\b(want to buy|need to buy|purchase|pick up|shopping list|groceries)\b').hasMatch(lower);
  }
}
