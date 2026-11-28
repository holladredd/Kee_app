import 'dart:convert';
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
  deviceAction,
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
  final Future<Map<String, dynamic>> Function(String action, String target)?
  _deviceActionHandler;
  final Uuid _uuid = const Uuid();
  String? _pendingDeleteMemoryId;
  String? _pendingDeleteMemoryTitle;

  KeeConversationEngine({
    required MemoryRepository memoryRepo,
    required ReminderRepository reminderRepo,
    NotificationService? notificationService,
    RecallEngine? recallEngine,
    Future<Map<String, dynamic>> Function(String action, String target)?
    deviceActionHandler,
  }) : _memoryRepo = memoryRepo,
       _reminderRepo = reminderRepo,
       _notificationService =
           notificationService ?? NotificationService.instance,
       _recallEngine = recallEngine ?? RecallEngine(),
       _deviceActionHandler = deviceActionHandler;

  /// Process any natural-language user message (voice or typed).
  Future<ConversationAction> processMessage(String rawInput) async {
    var text = rawInput.trim();

    // ─── 0. STRIP LEADING WAKE PHRASES & CONVERSATIONAL ADDRESSES ───
    // e.g. "Hi Kee, remember that I prefer coffee" -> "remember that I prefer coffee"
    // e.g. "What's up K, remind me to call John" -> "remind me to call John"
    final wakeMatch = RegExp(
      r'^(?:(?:hi|hey|hello|ok|okay|what\x27?s\s+up|whats\s+up|what\s+up)\s+(?:kee|k)|(?:hi|hey|hello|ok|okay)?\s*kee)\b[,\s!]*',
      caseSensitive: false,
    ).firstMatch(text);
    if (wakeMatch != null) {
      text = text.substring(wakeMatch.end).trim();
    }

    if (text.isEmpty) {
      return const ConversationAction(
        responseText:
            "I'm listening. Tell me something to remember or ask me anything you've saved.",
        intent: MessageIntent.casualConversation,
      );
    }

    final lower = text.toLowerCase();

    // ─── 0.5. PENDING DESTRUCTIVE DELETE CONFIRMATION ──────────────
    if (_pendingDeleteMemoryId != null) {
      return await _handlePendingDeleteConfirmation(lower);
    }

    // ─── 1. GREETINGS & CASUAL CONVERSATION (Do NOT save junk) ───
    if (_isCasualGreeting(lower)) {
      return ConversationAction(
        responseText: _generateGreetingResponse(lower),
        intent: MessageIntent.casualConversation,
      );
    }

    // ─── 2. GENERAL KNOWLEDGE / WEATHER CHITCHAT (Do NOT pollute memory search) ───
    // e.g. "What's the weather like?", "What time is it?"
    if (_isGeneralChitchatQuestion(lower)) {
      return ConversationAction(
        responseText: _generateChitchatResponse(lower),
        intent: MessageIntent.casualConversation,
      );
    }

    // ─── 2.5. SENSITIVE CREDENTIALS GUARD (Never auto-store) ───────
    if (_isSensitiveCredential(lower)) {
      return const ConversationAction(
        responseText:
            "For your security, I don't automatically store passwords, PINs, or authentication codes. Please keep sensitive credentials in a dedicated password manager.",
        intent: MessageIntent.casualConversation,
      );
    }

    // ─── 3. PREFERENCE UPDATE / CORRECTION ────────────────────────
    // e.g. "I no longer prefer dark mode. I prefer light mode."
    // e.g. "Change my preference for coffee to tea."
    if (_isPreferenceUpdate(lower)) {
      return await _handlePreferenceUpdate(text);
    }

    // ─── 3.5. EXPLICIT FORGET / DELETE OR MEMORY UPDATE ───────────
    final forgetTarget = _extractForgetTarget(text);
    if (forgetTarget != null) {
      return await _handleForgetRequest(forgetTarget);
    }
    final updateRequest = _extractMemoryUpdateRequest(text);
    if (updateRequest != null) {
      return await _handleMemoryUpdateRequest(
        updateRequest.$1,
        updateRequest.$2,
      );
    }

    // ─── 4. EXPLICIT MEMORY COMMAND PREFIXES ──────────────────────
    // e.g. "Remember that...", "Please remember...", "Can you remember...",
    //      "Save that...", "Note that...", "Record that...", "Store this..."
    final explicitMatch = RegExp(
      r'^(?:(?:please\s+|can\s+you\s+|could\s+you\s+|would\s+you\s+|help\s+me\s+)?(?:remember(?:\s+that|\s+this)?|don\x27?t\s+forget(?:\s+that|\s+this)?|keep\s+this\s+in\s+mind(?:\s+that)?|keep\s+in\s+mind(?:\s+that)?|save\s+this\s+for\s+later|save\s+that\s+for\s+later|save\s+this|save\s+that|note\s+that|note\s+this|record\s+that|record\s+this|store\s+this|store\s+that)|i\s+want\s+you\s+to\s+know\s+that|this\s+is\s+important\s+to\s+me)[,:\s]+',
      caseSensitive: false,
    ).firstMatch(text);

    String effectiveText = text;
    bool isExplicitSave = false;
    if (explicitMatch != null) {
      isExplicitSave = true;
      effectiveText = text
          .substring(explicitMatch.end)
          .replaceAll(RegExp(r'\?+$'), '')
          .trim();
      if (effectiveText.isEmpty) effectiveText = text;
    }
    final effectiveLower = effectiveText.toLowerCase();

    // ─── 4.5. DEVICE & APP ACTIONS (Open apps, Phone book, Make calls) ───
    if (!isExplicitSave) {
      final deviceAction = await _tryHandleDeviceAction(
        effectiveText,
        effectiveLower,
      );
      if (deviceAction != null) return deviceAction;
    }

    // ─── 5. QUERIES & RETRIEVAL INTENT ────────────────────────────
    // If user is asking a question about memories, tasks, reminders, or facts
    if (!isExplicitSave && _isQueryIntent(effectiveLower)) {
      return await _handleQuery(effectiveText);
    }

    // ─── 6. EXPLICIT REMINDER / APPOINTMENT / SCHEDULE INTENT ──────
    // e.g. "Remind me to call John tomorrow at 9 AM" or "I have an appointment Friday at 2 PM"
    if (_isReminderIntent(effectiveLower) ||
        _isScheduleOrAppointment(effectiveLower)) {
      return await _handleReminder(effectiveText);
    }

    // ─── 7. PERSONAL PREFERENCE INTENT ────────────────────────────
    // e.g. "I prefer dark mode", "Remember that I prefer coffee"
    if (_isPreferenceIntent(effectiveLower)) {
      return await _handlePreference(effectiveText);
    }

    // ─── 8. IMPORTANT DATE / BIRTHDAY / FACT ──────────────────────
    // e.g. "My birthday is March 12", "My mum's birthday is February 14"
    if (_isImportantDateOrFact(effectiveLower)) {
      return await _handleImportantDateOrFact(effectiveText);
    }

    // ─── 9. IDEA / INTENTION ──────────────────────────────────────
    // e.g. "I want to buy a laptop", "I have an idea for an app"
    if (_isIdeaOrIntentionIntent(effectiveLower)) {
      return await _handleIdeaOrIntention(effectiveText);
    }

    // ─── 10. ACTIVE SHOPPING / TASK ───────────────────────────────
    // e.g. "Need to buy groceries", "Pick up milk from store"
    if (_isShoppingOrTaskIntent(effectiveLower)) {
      return await _handleShoppingOrTask(effectiveText);
    }

    // ─── 11. EXPLICIT SAVE OR CLEAR PERSONAL EXPERIENCE/FACT ONLY ─
    // Never save every random spoken sentence automatically.
    if (isExplicitSave || _isPersonalExperienceOrFact(effectiveLower)) {
      return await _handleEventOrGeneralMemory(effectiveText);
    }

    // ─── 12. UNCLEAR / CASUAL UTTERANCE (Do NOT save; ask or converse) ─
    return ConversationAction(
      responseText:
          "I didn't save that automatically. Would you like me to remember it, set a reminder, or help you open an app or make a call?",
      intent: MessageIntent.casualConversation,
      requiresClarification: true,
    );
  }

  Future<ConversationAction> _dispatchDeviceAction(
    String action,
    String target, {
    String? fallbackMessage,
  }) async {
    if (_deviceActionHandler != null) {
      final res = await _deviceActionHandler(action, target);
      final msg =
          res['message'] as String? ?? fallbackMessage ?? 'Action completed.';
      return ConversationAction(
        responseText: msg,
        intent: MessageIntent.deviceAction,
      );
    }
    return ConversationAction(
      responseText: fallbackMessage ?? 'Executing $action.',
      intent: MessageIntent.deviceAction,
    );
  }

  Future<ConversationAction?> _tryHandleDeviceAction(
    String text,
    String lower,
  ) async {
    final trimmed = text.trim();
    final cleanLower = lower.replaceAll(RegExp(r'[.!?]+$'), '').trim();

    // 1. Return to home screen
    if (RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:return|go)\s+(?:to\s+)?(?:the\s+)?home(?:\s+screen)?$',
    ).hasMatch(cleanLower)) {
      return _dispatchDeviceAction(
        'goHome',
        '',
        fallbackMessage: 'Returning to the home screen.',
      );
    }

    // 2. Flashlight control
    final flashMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:(?:turn|switch)\s+(on|off)\s+(?:the\s+)?(?:flashlight|torch)|(?:turn|switch)\s+(?:the\s+)?(?:flashlight|torch)\s+(on|off)|(?:flashlight|torch)\s+(on|off))$',
    ).firstMatch(cleanLower);
    if (flashMatch != null) {
      final stateWord =
          flashMatch.group(1) ?? flashMatch.group(2) ?? flashMatch.group(3);
      final enabled = stateWord == 'on';
      return _dispatchDeviceAction(
        'setFlashlight',
        jsonEncode({'enabled': enabled}),
        fallbackMessage: enabled
            ? 'Flashlight turned on.'
            : 'Flashlight turned off.',
      );
    }

    // 3. Set an alarm
    final alarmMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:set|create|add)\s+(?:an\s+)?alarm(?:\s+(?:for|at)\s+(.+))?$',
    ).firstMatch(cleanLower);
    if (alarmMatch != null) {
      final timePart = alarmMatch.group(1)?.trim() ?? '';
      final alarmTime = _parseAlarmTime(timePart);
      if (alarmTime == null) {
        return const ConversationAction(
          responseText: 'What time should I set the alarm for?',
          intent: MessageIntent.deviceAction,
          requiresClarification: true,
        );
      }
      final (hour, minute) = alarmTime;
      final formatted = DateFormat(
        'h:mm a',
      ).format(DateTime(2026, 1, 1, hour, minute));
      return _dispatchDeviceAction(
        'setAlarm',
        jsonEncode({'hour': hour, 'minute': minute, 'label': 'Kee Alarm'}),
        fallbackMessage: 'Setting an alarm for $formatted.',
      );
    }

    // 4. Adjust volume
    final volumeMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:(?:turn|adjust|set)\s+(?:the\s+)?volume\s*(up|down|higher|lower)?|volume\s+(up|down)|adjust\s+(?:the\s+)?volume|(mute|unmute)(?:\s+(?:the\s+)?(?:volume|media|sound))?)$',
    ).firstMatch(cleanLower);
    if (volumeMatch != null) {
      final rawDir =
          volumeMatch.group(1) ?? volumeMatch.group(2) ?? volumeMatch.group(3);
      if (rawDir == null) {
        return const ConversationAction(
          responseText:
              'Would you like me to turn the volume up, down, or mute it?',
          intent: MessageIntent.deviceAction,
          requiresClarification: true,
        );
      }
      final direction = switch (rawDir) {
        'higher' || 'up' => 'up',
        'lower' || 'down' => 'down',
        'mute' => 'mute',
        'unmute' => 'unmute',
        _ => 'up',
      };
      return _dispatchDeviceAction(
        'adjustVolume',
        jsonEncode({'direction': direction}),
        fallbackMessage: 'Adjusting volume $direction.',
      );
    }

    // 5. Open dialer / Show recent calls
    if (RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:open|launch|show)\s+(?:the\s+)?(?:phone\s+)?dialer$',
    ).hasMatch(cleanLower)) {
      return _dispatchDeviceAction(
        'openDialer',
        '',
        fallbackMessage: 'Opening the dialer.',
      );
    }
    if (RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:show|open|view|check)\s+(?:my\s+)?recent\s+calls$',
    ).hasMatch(cleanLower)) {
      return _dispatchDeviceAction(
        'recentCalls',
        '',
        fallbackMessage: 'Opening Phone for your recent calls.',
      );
    }

    // 6. Make a phone call (no target) or Call contact/number
    if (RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+|i\s+want\s+to\s+)?(?:make|place|start)\s+(?:a\s+)?(?:phone\s+)?call$',
    ).hasMatch(cleanLower)) {
      return const ConversationAction(
        responseText: 'Who would you like me to call?',
        intent: MessageIntent.deviceAction,
        requiresClarification: true,
      );
    }

    final callMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+|would\s+you\s+|i\s+want\s+to\s+)?(?:make\s+a\s+(?:phone\s+)?call\s+to|call|dial|phone|ring)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (callMatch != null && !cleanLower.contains('remind me')) {
      final target = callMatch
          .group(1)!
          .replaceAll(RegExp(r'[.!?]+$'), '')
          .trim();
      if (target.isNotEmpty) {
        return _dispatchDeviceAction(
          'callContact',
          target,
          fallbackMessage: 'Calling $target.',
        );
      }
    }

    // 7. Communication: Open messages, WhatsApp message, Compose SMS
    if (RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:open|launch|show)\s+(?:my\s+)?messages(?:\s+app)?$',
    ).hasMatch(cleanLower)) {
      return _dispatchDeviceAction(
        'openMessages',
        '',
        fallbackMessage: 'Opening Messages.',
      );
    }

    final whatsappMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:send|write|compose)\s+(?:a\s+)?whatsapp\s+message(?:\s+to\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (whatsappMatch != null) {
      final target = (whatsappMatch.group(1) ?? '')
          .replaceAll(RegExp(r'[.!?]+$'), '')
          .trim();
      return _dispatchDeviceAction(
        'whatsappMessage',
        jsonEncode({'target': target, 'body': ''}),
        fallbackMessage: 'Opening WhatsApp.',
      );
    }

    final smsMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:(?:compose|send|write)\s+(?:an\s+|a\s+)?(?:sms|text(?:\s+message)?|message)(?:\s+to\s+(.+))?|text\s+(.+))$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (smsMatch != null) {
      final target = (smsMatch.group(1) ?? smsMatch.group(2) ?? '')
          .replaceAll(RegExp(r'[.!?]+$'), '')
          .trim();
      return _dispatchDeviceAction(
        'composeSms',
        jsonEncode({'target': target, 'body': ''}),
        fallbackMessage: target.isNotEmpty
            ? 'Opening your SMS composer for $target.'
            : 'Opening your SMS composer.',
      );
    }

    // 8. App control: Close app, Switch apps, Open app
    final closeMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+|would\s+you\s+)?(?:close|exit|quit|kill|force\s+stop|shut\s+down)\s+(?:the\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (closeMatch != null) {
      final target = closeMatch
          .group(1)!
          .replaceAll(RegExp(r'[.!?]+$'), '')
          .trim();
      if (target.isNotEmpty) {
        return _dispatchDeviceAction(
          'closeApp',
          jsonEncode({'target': target}),
          fallbackMessage:
              "I can't force-close $target because Android doesn't allow assistant apps to close other apps without system or Accessibility permission.",
        );
      }
    }

    final switchMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?switch\s+(?:to\s+(.+)|apps?)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (switchMatch != null) {
      final target = (switchMatch.group(1) ?? '')
          .replaceAll(RegExp(r'[.!?]+$'), '')
          .trim();
      return _dispatchDeviceAction(
        'switchApp',
        jsonEncode({'target': target}),
        fallbackMessage: target.isNotEmpty
            ? 'Opening $target.'
            : 'Tell me which app you would like to switch to.',
      );
    }

    final openMatch = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+|would\s+you\s+)?(?:open|launch|start)\s+(?:my\s+|the\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (openMatch != null) {
      final target = openMatch
          .group(1)!
          .replaceAll(RegExp(r'[.!?]+$'), '')
          .trim();
      if (target.isNotEmpty) {
        return _dispatchDeviceAction(
          'openApp',
          target,
          fallbackMessage: 'Opening $target.',
        );
      }
    }

    // 9. Unsupported system/device action guard (never fall through to memory prompt)
    if (RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:take\s+a\s+(?:screenshot|photo|picture)|(?:turn|switch)\s+(?:on|off)\s+(?:wi-?fi|bluetooth|airplane\s+mode|mobile\s+data|hotspot)|lock\s+(?:the\s+)?screen|restart\s+(?:the\s+)?(?:phone|device)|power\s+off|shut\s+down\s+(?:the\s+)?(?:phone|device)|(?:increase|decrease|adjust)\s+(?:the\s+)?brightness)\b',
    ).hasMatch(cleanLower)) {
      return const ConversationAction(
        responseText:
            "I recognized that as a device-control request, but Kee doesn't support that system action on Android without system or Accessibility permissions.",
        intent: MessageIntent.deviceAction,
      );
    }

    return null;
  }

  (int, int)? _parseAlarmTime(String timePart) {
    if (timePart.isEmpty) return null;
    final direct = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b',
      caseSensitive: false,
    ).firstMatch(timePart);
    if (direct != null) {
      var hour = int.tryParse(direct.group(1) ?? '');
      final minute = int.tryParse(direct.group(2) ?? '0') ?? 0;
      final meridiem = direct.group(3)?.toLowerCase();
      if (hour != null && minute >= 0 && minute <= 59) {
        if (meridiem == 'pm' && hour < 12) hour += 12;
        if (meridiem == 'am' && hour == 12) hour = 0;
        if (hour >= 0 && hour <= 23) {
          return (hour, minute);
        }
      }
    }
    final parsed = NlpDateParser.parse(timePart);
    final dt = parsed.dateTime;
    if (dt != null) {
      return (dt.hour, dt.minute);
    }
    return null;
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
        responseText:
            "When would you like to be reminded about '$title'? (e.g. tomorrow at 9 AM, in 2 hours, or Friday at 3 PM)",
        intent: MessageIntent.reminder,
        requiresClarification: true,
      );
    }

    final scheduledDate = dateResult.dateTime!;
    final title = classification.title;
    final now = DateTime.now();

    if (scheduledDate.isBefore(now)) {
      return ConversationAction(
        responseText:
            "That time appears to be in the past (${DateFormat('MMM d, h:mm a').format(scheduledDate)}). When should I schedule it?",
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
    // 2. Save underlying Task in SQLite
    final task = TaskModel(
      id: taskId,
      memoryId: memoryId,
      title: title,
      priority: 'high',
      dueDate: scheduledDate,
      dueTime:
          '${scheduledDate.hour.toString().padLeft(2, '0')}:${scheduledDate.minute.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
    );

    // 3. Save Memory record for recall
    final memory = MemoryModel(
      id: memoryId,
      title: title,
      originalContent: text,
      processedContent:
          'Reminder scheduled for ${DateFormat('EEEE, MMM d, yyyy @ h:mm a').format(scheduledDate)}',
      memoryType: 'reminder',
      category: classification.category,
      tags: ['reminder', ...classification.tags],
      associatedPerson: classification.associatedPerson,
      associatedDate: scheduledDate,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _reminderRepo.createReminder(reminder);
      await _reminderRepo.createTask(task);
      await _memoryRepo.createMemory(memory);
    } catch (e) {
      return const ConversationAction(
        responseText:
            "I couldn't save that reminder right now because storage failed. Please try again.",
        intent: MessageIntent.reminder,
      );
    }

    // 4. Schedule local notification on device
    final notificationId =
        scheduledDate.millisecondsSinceEpoch ~/ 1000 % 1000000;
    await _notificationService.scheduleReminder(
      notificationId: notificationId,
      title: 'Kee Reminder',
      body: title,
      scheduledDate: scheduledDate,
    );

    final timeStr = DateFormat('EEEE, MMM d @ h:mm a').format(scheduledDate);
    final recur = dateResult.recurrenceRule != null
        ? ' (recurring ${dateResult.recurrenceRule})'
        : '';

    return ConversationAction(
      responseText:
          "I've set a reminder for **$title** on **$timeStr**$recur. I'll notify you on your device when it's time.",
      intent: MessageIntent.reminder,
      savedMemory: memory,
      scheduledReminder: reminder,
      savedTask: task,
    );
  }

  Future<ConversationAction> _handlePreference(String text) async {
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();

    // Check for existing preference with similar title or keywords to prevent duplicates
    final existingMemories = await _memoryRepo.getAllMemories();
    MemoryModel? existing;
    for (final m in existingMemories) {
      if (m.memoryType == 'personal_preference') {
        final titleA = m.title.toLowerCase();
        final titleB = classification.title.toLowerCase();
        if (titleA == titleB ||
            m.originalContent.toLowerCase() == text.toLowerCase() ||
            (titleA.contains('dark') && titleB.contains('dark')) ||
            (titleA.contains('light') && titleB.contains('light')) ||
            (titleA.contains('coffee') && titleB.contains('coffee'))) {
          existing = m;
          break;
        }
      }
    }

    if (existing != null) {
      // Update existing preference
      final updated = existing.copyWith(
        title: classification.title,
        originalContent: text,
        processedContent: 'User preference: ${classification.title}',
        updatedAt: now,
      );
      try {
        await _memoryRepo.updateMemory(updated);
      } catch (e) {
        return const ConversationAction(
          responseText:
              "I couldn't update that preference right now because storage failed. Please try again.",
          intent: MessageIntent.preference,
        );
      }
      return ConversationAction(
        responseText:
            "I've updated your preference for **${classification.title}**.",
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
    try {
      await _memoryRepo.createMemory(memory);
    } catch (e) {
      return const ConversationAction(
        responseText:
            "I couldn't save that preference right now because storage failed. Please try again.",
        intent: MessageIntent.preference,
      );
    }

    return ConversationAction(
      responseText:
          "Got it. I've remembered your preference: **${classification.title}**.",
      intent: MessageIntent.preference,
      savedMemory: memory,
    );
  }

  /// Handles preference updates/corrections:
  /// e.g. "I no longer prefer dark mode. I prefer light mode."
  Future<ConversationAction> _handlePreferenceUpdate(String text) async {
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();
    final lower = text.toLowerCase();

    final existingMemories = await _memoryRepo.getAllMemories();
    MemoryModel? target;

    // Look for existing preference memory to supersede
    for (final m in existingMemories) {
      if (m.memoryType == 'personal_preference') {
        final mLower = '${m.title} ${m.originalContent}'.toLowerCase();
        // Check for domain overlap (e.g. mode/theme, beverage, music)
        if ((mLower.contains('mode') || mLower.contains('theme')) &&
            (lower.contains('mode') || lower.contains('theme'))) {
          target = m;
          break;
        } else if ((mLower.contains('coffee') || mLower.contains('tea')) &&
            (lower.contains('coffee') || lower.contains('tea'))) {
          target = m;
          break;
        }
      }
    }

    // Determine new preference title
    String newTitle = classification.title;
    if (lower.contains('prefer light mode') || lower.contains('light mode')) {
      newTitle = 'Light mode';
    } else if (lower.contains('prefer dark mode') ||
        lower.contains('dark mode')) {
      newTitle = 'Dark mode';
    }

    if (target != null) {
      final updated = target.copyWith(
        title: 'Prefers $newTitle',
        originalContent: text,
        processedContent: 'User preference: $newTitle (updated)',
        updatedAt: now,
      );
      await _memoryRepo.updateMemory(updated);
      return ConversationAction(
        responseText: "I've updated your preference to **$newTitle**.",
        intent: MessageIntent.preference,
        savedMemory: updated,
      );
    }

    // If no existing match, save as new preference
    return _handlePreference(text);
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
    try {
      await _memoryRepo.createMemory(memory);
    } catch (e) {
      return const ConversationAction(
        responseText:
            "I couldn't save that memory right now because storage failed. Please try again.",
        intent: MessageIntent.importantDate,
      );
    }

    final personNotice = classification.associatedPerson != null
        ? " for ${classification.associatedPerson}"
        : "";
    final dateNotice = dateResult.dateTime != null
        ? " on ${DateFormat('MMMM d').format(dateResult.dateTime!)}"
        : "";

    return ConversationAction(
      responseText:
          "I've made a note of **${classification.title}**$personNotice$dateNotice. I'll have it ready whenever you ask.",
      intent: MessageIntent.importantDate,
      savedMemory: memory,
    );
  }

  Future<ConversationAction> _handleIdeaOrIntention(String text) async {
    final classification = DeterministicClassifier.classify(text);
    final now = DateTime.now();

    final memory = MemoryModel(
      id: _uuid.v4(),
      title: classification.title,
      originalContent: text,
      memoryType: 'idea',
      category: 'Ideas',
      tags: ['idea', 'intention', ...classification.tags],
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _memoryRepo.createMemory(memory);
    } catch (e) {
      return const ConversationAction(
        responseText:
            "I couldn't save that idea right now because storage failed. Please try again.",
        intent: MessageIntent.idea,
      );
    }

    return ConversationAction(
      responseText:
          "I've saved **${classification.title}** in your ideas & intentions. You can revisit it anytime.",
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
    final task = TaskModel(
      id: taskId,
      memoryId: memoryId,
      title: classification.title,
      priority: 'normal',
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _memoryRepo.createMemory(memory);
      await _reminderRepo.createTask(task);
    } catch (e) {
      return const ConversationAction(
        responseText:
            "I couldn't save that commitment right now because storage failed. Please try again.",
        intent: MessageIntent.shoppingOrTask,
      );
    }

    return ConversationAction(
      responseText:
          "I've saved **${classification.title}** to your commitments.",
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
      memoryType: classification.memoryType == 'experience'
          ? 'experience'
          : 'personal_memory',
      category: classification.category,
      tags: classification.tags,
      associatedPerson: classification.associatedPerson,
      associatedDate: classification.associatedDate,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _memoryRepo.createMemory(memory);
    } catch (e) {
      return const ConversationAction(
        responseText:
            "I couldn't save that memory right now because storage failed. Please try again.",
        intent: MessageIntent.eventOrFact,
      );
    }

    return ConversationAction(
      responseText: "Noted. I've remembered this: **${classification.title}**.",
      intent: MessageIntent.eventOrFact,
      savedMemory: memory,
    );
  }

  Future<ConversationAction> _handlePendingDeleteConfirmation(
    String lower,
  ) async {
    final id = _pendingDeleteMemoryId!;
    final title = _pendingDeleteMemoryTitle ?? 'that memory';
    final isConfirm = RegExp(
      r'^(yes|yeah|yep|confirm|do it|go ahead|delete it|forget it|please|sure)\b',
    ).hasMatch(lower);
    final isCancel = RegExp(
      r'^(no|nope|cancel|never mind|nevermind|keep it|stop|don\x27?t)\b',
    ).hasMatch(lower);

    if (isConfirm) {
      _pendingDeleteMemoryId = null;
      _pendingDeleteMemoryTitle = null;
      try {
        await _memoryRepo.deleteMemory(id);
        return ConversationAction(
          responseText: "I've forgotten **$title**.",
          intent: MessageIntent.casualConversation,
        );
      } catch (e) {
        return const ConversationAction(
          responseText:
              "I couldn't delete that memory right now because storage failed. Your memory is still intact.",
          intent: MessageIntent.casualConversation,
        );
      }
    }

    if (isCancel) {
      _pendingDeleteMemoryId = null;
      _pendingDeleteMemoryTitle = null;
      return ConversationAction(
        responseText: "Okay, I kept **$title**.",
        intent: MessageIntent.casualConversation,
      );
    }

    return ConversationAction(
      responseText:
          "Please confirm: should I forget **$title**? Say yes to delete or no to keep it.",
      intent: MessageIntent.casualConversation,
      requiresClarification: true,
    );
  }

  String? _extractForgetTarget(String text) {
    final match = RegExp(
      r'^(?:please\s+|can\s+you\s+|could\s+you\s+)?(?:forget|delete|remove)\s+(?:the\s+memory\s+(?:about|of)\s+|my\s+memory\s+(?:about|of)\s+|that\s+|about\s+)?(.+?)(?:\s+from\s+(?:my\s+)?memory)?[\.?!]*$',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (match == null) return null;
    final target = match.group(1)?.trim() ?? '';
    return target.isEmpty ? null : target;
  }

  Future<ConversationAction> _handleForgetRequest(String target) async {
    final matches = await _findMatchingMemories(target);
    if (matches.isEmpty) {
      return ConversationAction(
        responseText: "I couldn't find any saved memory matching \"$target\".",
        intent: MessageIntent.casualConversation,
      );
    }
    if (matches.length > 1) {
      final options = matches.take(3).map((m) => '**${m.title}**').join(', ');
      return ConversationAction(
        responseText:
            "I found multiple memories matching \"$target\": $options. Which one should I forget?",
        intent: MessageIntent.casualConversation,
        requiresClarification: true,
        citedMemories: matches.take(3).toList(),
      );
    }

    final match = matches.first;
    _pendingDeleteMemoryId = match.id;
    _pendingDeleteMemoryTitle = match.title;
    return ConversationAction(
      responseText:
          "Are you sure you want me to forget **${match.title}**? Say yes to confirm or no to keep it.",
      intent: MessageIntent.casualConversation,
      requiresClarification: true,
      citedMemories: [match],
    );
  }

  (String, String)? _extractMemoryUpdateRequest(String text) {
    final match = RegExp(
      r'^(?:please\s+)?(?:update|change)\s+(?:my\s+memory\s+(?:about|for)\s+|the\s+memory\s+(?:about|for)\s+|my\s+)?(.+?)\s+to\s+(.+?)[\.?!]*$',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (match == null) return null;
    final target = match.group(1)?.trim() ?? '';
    final newValue = match.group(2)?.trim() ?? '';
    if (target.isEmpty || newValue.isEmpty) return null;
    return (target, newValue);
  }

  Future<ConversationAction> _handleMemoryUpdateRequest(
    String target,
    String newValue,
  ) async {
    if (_isSensitiveCredential(newValue.toLowerCase())) {
      return const ConversationAction(
        responseText:
            "For your security, I don't automatically store passwords, PINs, or authentication codes.",
        intent: MessageIntent.casualConversation,
      );
    }

    final matches = await _findMatchingMemories(target);
    if (matches.isEmpty) {
      return ConversationAction(
        responseText:
            "I couldn't find an existing memory matching \"$target\" to update.",
        intent: MessageIntent.casualConversation,
      );
    }
    if (matches.length > 1) {
      final options = matches.take(3).map((m) => '**${m.title}**').join(', ');
      return ConversationAction(
        responseText:
            "I found multiple memories matching \"$target\": $options. Which one would you like to update?",
        intent: MessageIntent.casualConversation,
        requiresClarification: true,
        citedMemories: matches.take(3).toList(),
      );
    }

    final existing = matches.first;
    final updated = existing.copyWith(
      title: newValue,
      originalContent: '$target: $newValue',
      updatedAt: DateTime.now(),
    );
    try {
      await _memoryRepo.updateMemory(updated);
      return ConversationAction(
        responseText: "I've updated **${existing.title}** to **$newValue**.",
        intent: MessageIntent.eventOrFact,
        savedMemory: updated,
      );
    } catch (e) {
      return const ConversationAction(
        responseText:
            "I couldn't update that memory right now because storage failed. Please try again.",
        intent: MessageIntent.eventOrFact,
      );
    }
  }

  Future<List<MemoryModel>> _findMatchingMemories(String query) async {
    final all = await _memoryRepo.getAllMemories();
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    if (terms.isEmpty) return [];
    return all.where((m) {
      final haystack = '${m.title} ${m.originalContent} ${m.category}'
          .toLowerCase();
      return terms.any((t) => haystack.contains(t));
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────
  // INTENT RECOGNITION HELPERS
  // ─────────────────────────────────────────────────────────────

  bool _isCasualGreeting(String lower) {
    return RegExp(
          r'^(hi|hello|hey|good morning|good afternoon|good evening|howdy|sup|greetings)(\s+kee)?[\.!]?$',
        ).hasMatch(lower) ||
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
    if (lower.contains('who are you') ||
        lower.contains('what can you do') ||
        lower.contains('help')) {
      return "I am Kee (Knowledge Extension Entity)—your personal AI memory assistant.\n\n"
          "You can simply talk to me:\n"
          "• Tell me things to remember: *'My birthday is March 12'*, *'I prefer dark mode'*, *'I met David at the tech summit'*\n"
          "• Schedule reminders: *'Remind me to call John tomorrow at 9 AM'*\n"
          "• Ask questions: *'What did I say about David?'*, *'What do I have tomorrow?'*\n\n"
          "Everything is securely stored and processed right on your device. Your memory. Extended.";
    }
    return "Hello! I'm Kee, ready to extend your memory. What's on your mind today?";
  }

  bool _isGeneralChitchatQuestion(String lower) {
    return RegExp(
      r'\b(weather|temperature|forecast|rain|snow|what time is it|current time|what day is it|tell me a joke|meaning of life)\b',
    ).hasMatch(lower);
  }

  String _generateChitchatResponse(String lower) {
    if (lower.contains('weather') ||
        lower.contains('temperature') ||
        lower.contains('forecast') ||
        lower.contains('rain')) {
      return "I don't have access to live weather broadcasts, but I'm always ready to help you save memories, manage preferences, and schedule reminders.";
    }
    if (lower.contains('time') || lower.contains('day')) {
      final now = DateTime.now();
      return "Currently, it's ${DateFormat('EEEE, MMMM d, yyyy · h:mm a').format(now)}.";
    }
    if (lower.contains('joke')) {
      return "Why do programmers prefer dark mode? Because light attracts bugs!";
    }
    return "I am here to help you remember and organize what matters.";
  }

  bool _isPreferenceUpdate(String lower) {
    return RegExp(
      r"\b(no longer prefer|don'?t like .* anymore|change my preference|actually .* prefer|instead of .* i prefer)\b",
    ).hasMatch(lower);
  }

  bool _isQueryIntent(String lower) {
    return lower.endsWith('?') ||
        RegExp(
          r'\b(what did i|what was|what are my|what do i have|which|when is|who is|where did|did i|have i|tell me about|recall|search)\b',
        ).hasMatch(lower);
  }

  bool _isReminderIntent(String lower) {
    return RegExp(
      r"\b(remind me|alert me to|notify me|set a reminder|don'?t forget to)\b",
    ).hasMatch(lower);
  }

  bool _isScheduleOrAppointment(String lower) {
    return RegExp(
      r'\b(appointment|schedule|meeting with|doctor.?s? visit|dentist|flight at|interview)\b',
    ).hasMatch(lower);
  }

  bool _isSensitiveCredential(String lower) {
    return RegExp(
      r'\b(password|passcode|pin\s*code|my\s+pin\b|otp|one[\s-]?time\s+password|2fa|two[\s-]?factor|auth(?:entication)?\s+code|verification\s+code|secret\s+key|api\s+key|private\s+key|cvv|social\s+security|ssn)\b',
    ).hasMatch(lower);
  }

  bool _isPersonalExperienceOrFact(String lower) {
    return RegExp(
      r'\b(i\s+met|i\s+attended|i\s+visited|i\s+went\s+to|i\s+saw|i\s+graduated|i\s+studied|i\s+work\s+(?:at|for|as)|i\s+live\s+in|i\s+moved\s+to|i\s+am\s+allergic\s+to|i\s+parked|i\s+put\s+my|i\s+have\s+a\s+(?:dog|cat|pet)|i\s+usually|every\s+(?:morning|evening|day|week)\s+i|my\s+name\s+is|my\s+phone\s+number\s+is|my\s+email\s+is|my\s+address\s+is|my\s+office\s+is|my\s+car\s+is|my\s+doctor\s+is|my\s+routine\s+is|my\s+locker\s+is|my\s+keys\s+are)\b',
    ).hasMatch(lower);
  }

  bool _isPreferenceIntent(String lower) {
    return RegExp(
      r'\b(i prefer|my preference|i always like|i love|i hate|i dislike|my favorite|my favourite)\b',
    ).hasMatch(lower);
  }

  bool _isImportantDateOrFact(String lower) {
    return RegExp(
      r'\b(birthday|anniversary|warranty|renewal|contract ends|expires?|due date)\b',
    ).hasMatch(lower);
  }

  bool _isIdeaOrIntentionIntent(String lower) {
    return RegExp(
      r'\b(want to buy|thinking of buying|planning to buy|considering buying|idea for|what if we|thought about making|concept for|brainstorm)\b',
    ).hasMatch(lower);
  }

  bool _isShoppingOrTaskIntent(String lower) {
    return RegExp(
      r'\b(need to buy|must buy|pick up from store|shopping list|groceries|need to|have to|must)\b',
    ).hasMatch(lower);
  }
}
