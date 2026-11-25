import '../../features/memories/data/memory_model.dart';
import '../../features/reminders/data/task_model.dart';
import '../../features/reminders/data/reminder_model.dart';
import 'ai_abstraction.dart';
import 'deterministic_classifier.dart';

class RecallEngine implements AiAssistantEngine {
  @override
  String get name => 'Deterministic Recall Engine (Offline)';

  @override
  String get status => 'ready';

  @override
  Future<ClassificationResult> understandInput(String rawText) async {
    return DeterministicClassifier.classify(rawText);
  }

  @override
  Future<String> classifyMemory(String text) async {
    final result = DeterministicClassifier.classify(text);
    return result.memoryType;
  }

  @override
  Future<ClassificationResult> extractReminder(String text) async {
    return DeterministicClassifier.classify(text);
  }

  @override
  Future<String> summariseMemories(List<MemoryModel> memories) async {
    if (memories.isEmpty) {
      return 'You currently have no saved memories.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Summary of ${memories.length} saved memories:');
    for (int i = 0; i < memories.length; i++) {
      final m = memories[i];
      buffer.writeln('${i + 1}. [${m.category}] ${m.title}');
    }
    return buffer.toString();
  }

  @override
  Future<RecallAnswer> answerFromMemories({
    required String question,
    required List<MemoryModel> memories,
    required List<TaskModel> tasks,
    required List<ReminderModel> reminders,
  }) async {
    final qLower = question.toLowerCase().trim();

    // 1. Check for Pending Tasks Question
    // e.g. "Which tasks have I not completed?", "What tasks are pending?"
    if (qLower.contains('task') || qLower.contains('todo') || qLower.contains('supposed to do') || qLower.contains('have i not completed')) {
      final pendingTasks = tasks.where((t) => !t.isCompleted).toList();
      if (pendingTasks.isNotEmpty) {
        final taskList = pendingTasks.map((t) {
          final due = t.dueDate != null ? ' (Due: ${t.dueDate!.month}/${t.dueDate!.day})' : '';
          return '• ${t.title}$due';
        }).join('\n');

        return RecallAnswer(
          text: 'Here are your uncompleted tasks:\n\n$taskList',
          citedTasks: pendingTasks,
          hasDirectMatch: true,
        );
      } else if (tasks.isNotEmpty) {
        return RecallAnswer(
          text: 'All of your tasks are currently completed! Great job.',
          hasDirectMatch: true,
        );
      }
    }

    // 2. Check for Upcoming Reminders Question
    // e.g. "What am I supposed to do tomorrow?", "What is coming up?"
    if (qLower.contains('tomorrow') || qLower.contains('coming up') || qLower.contains('upcoming') || qLower.contains('reminder')) {
      final now = DateTime.now();
      final isTomorrow = qLower.contains('tomorrow');
      final targetDay = isTomorrow ? now.add(const Duration(days: 1)) : now;

      final matchingReminders = reminders.where((r) {
        if (!r.isEnabled) return false;
        if (isTomorrow) {
          return r.scheduledAt.year == targetDay.year &&
                 r.scheduledAt.month == targetDay.month &&
                 r.scheduledAt.day == targetDay.day;
        }
        return r.scheduledAt.isAfter(now);
      }).toList();

      if (matchingReminders.isNotEmpty) {
        final reminderList = matchingReminders.map((r) {
          final timeStr = '${r.scheduledAt.hour.toString().padLeft(2, '0')}:${r.scheduledAt.minute.toString().padLeft(2, '0')}';
          return '• ${r.title} at $timeStr';
        }).join('\n');

        return RecallAnswer(
          text: isTomorrow
              ? 'Here is what you have scheduled for tomorrow:\n\n$reminderList'
              : 'Here are your upcoming scheduled reminders:\n\n$reminderList',
          citedReminders: matchingReminders,
          hasDirectMatch: true,
        );
      }
    }

    // 3. Check for Promises / Commitments Question
    // e.g. "What promises have I made that I haven't fulfilled?"
    if (qLower.contains('promise') || qLower.contains('commitment') || qLower.contains('unfulfilled')) {
      final commitments = memories.where((m) => m.memoryType == 'commitment').toList();
      if (commitments.isNotEmpty) {
        final list = commitments.map((c) => '• ${c.title} (${c.associatedPerson != null ? "To ${c.associatedPerson}" : "No person specified"})').join('\n');
        return RecallAnswer(
          text: 'Here are the commitments and promises you have saved:\n\n$list',
          citedMemories: commitments,
          hasDirectMatch: true,
        );
      }
    }

    // 4. Check for Shopping / Purchases Question
    // e.g. "What did I say I wanted to buy?"
    if (qLower.contains('buy') || qLower.contains('purchase') || qLower.contains('shopping')) {
      final shopping = memories.where((m) => m.memoryType == 'shopping' || m.category == 'Shopping').toList();
      if (shopping.isNotEmpty) {
        final list = shopping.map((s) => '• ${s.title}').join('\n');
        return RecallAnswer(
          text: 'Here are the items you mentioned wanting to buy:\n\n$list',
          citedMemories: shopping,
          hasDirectMatch: true,
        );
      }
    }

    // 5. Check for Ideas Question
    // e.g. "What was that idea I had last week?"
    if (qLower.contains('idea') || qLower.contains('concept') || qLower.contains('brainstorm')) {
      final ideas = memories.where((m) => m.memoryType == 'idea' || m.category == 'Ideas').toList();
      if (ideas.isNotEmpty) {
        final list = ideas.map((i) => '• ${i.title}: ${i.originalContent}').join('\n\n');
        return RecallAnswer(
          text: 'Here are the ideas you have recorded:\n\n$list',
          citedMemories: ideas,
          hasDirectMatch: true,
        );
      }
    }

    // 6. Check for Preferences Question
    // e.g. "What did I say about my preferred working hours?", "What are my preferences?"
    if (qLower.contains('prefer') || qLower.contains('preference') || qLower.contains('favorite') || qLower.contains('favourite')) {
      final prefs = memories.where((m) => m.memoryType == 'personal_preference').toList();
      if (prefs.isNotEmpty) {
        final list = prefs.map((p) => '• ${p.originalContent}').join('\n');
        return RecallAnswer(
          text: 'Here are your saved preferences:\n\n$list',
          citedMemories: prefs,
          hasDirectMatch: true,
        );
      } else {
        return RecallAnswer(
          text: "You haven't saved any personal preferences yet. Tell me things you prefer (e.g. *'I prefer dark mode'*, *'I prefer coffee'*) and I'll keep them in mind.",
          hasDirectMatch: false,
        );
      }
    }

    // 7. General Keyword Search across Memories
    // Extract keywords by filtering stop words
    final stopWords = {
      'what', 'was', 'the', 'name', 'of', 'that', 'i', 'did', 'say', 'about',
      'my', 'is', 'a', 'an', 'in', 'on', 'at', 'to', 'for', 'which', 'who',
      'where', 'when', 'how', 'have', 'had', 'been', 'do', 'does', 'tell', 'me'
    };

    final keywords = qLower
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(' ')
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toList();

    if (keywords.isNotEmpty) {
      final matched = memories.where((m) {
        final content = '${m.title} ${m.originalContent} ${m.tags.join(" ")} ${m.associatedPerson ?? ""}'.toLowerCase();
        return keywords.any((k) => content.contains(k));
      }).toList();

      if (matched.isNotEmpty) {
        // Sort by match count
        matched.sort((a, b) {
          final contentA = '${a.title} ${a.originalContent}'.toLowerCase();
          final contentB = '${b.title} ${b.originalContent}'.toLowerCase();
          final countA = keywords.where((k) => contentA.contains(k)).length;
          final countB = keywords.where((k) => contentB.contains(k)).length;
          return countB.compareTo(countA);
        });

        final top = matched.take(5).toList();
        final textList = top.map((m) => '• **${m.title}**: ${m.originalContent}').join('\n\n');

        return RecallAnswer(
          text: 'I found these relevant memories:\n\n$textList',
          citedMemories: top,
          hasDirectMatch: true,
        );
      }
    }

    // 8. Grounded Fallback: NEVER hallucinate!
    final aboutMatch = RegExp(r'\b(about|regarding)\s+([a-zA-Z0-9\s]+?)(\?|$)', caseSensitive: false).firstMatch(question);
    final subject = aboutMatch != null ? aboutMatch.group(2)?.trim() : null;

    if (subject != null && subject.isNotEmpty && subject.length < 30) {
      return RecallAnswer(
        text: "I couldn't find any saved memories about $subject.",
        hasDirectMatch: false,
      );
    }

    return RecallAnswer(
      text: 'I could not find any saved memories or reminders matching "$question".',
      hasDirectMatch: false,
    );
  }
}
