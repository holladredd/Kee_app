import 'nlp_date_parser.dart';

class ClassificationResult {
  final String title;
  final String memoryType; // task, reminder, personal_memory, idea, commitment, personal_preference, important_date, reference, shopping, general_note
  final String category; // Work, Personal, Shopping, Ideas, Commitments, Finance, Health, General
  final List<String> tags;
  final String? associatedPerson;
  final DateTime? associatedDate;
  final String? recurrenceRule;
  final bool shouldCreateTask;
  final bool shouldCreateReminder;
  final String? clarificationNeeded;

  ClassificationResult({
    required this.title,
    required this.memoryType,
    required this.category,
    this.tags = const [],
    this.associatedPerson,
    this.associatedDate,
    this.recurrenceRule,
    this.shouldCreateTask = false,
    this.shouldCreateReminder = false,
    this.clarificationNeeded,
  });
}

class DeterministicClassifier {
  DeterministicClassifier._();

  static ClassificationResult classify(String input) {
    final trimmed = input.trim();
    final lower = trimmed.toLowerCase();

    // 1. Check for Ideas FIRST so we never mistake ideas for tasks!
    // Example: "I have an idea for an application that helps farmers manage their farms."
    if (RegExp(r'\b(idea|what if|thought about making|concept for|brainstorm)\b').hasMatch(lower)) {
      final title = _generateTitle(trimmed, prefixToRemove: ['i have an idea for', 'idea:', 'an idea for', 'what if']);
      return ClassificationResult(
        title: title,can i v
        memoryType: 'idea',
        category: 'Ideas',
        tags: ['idea', ..._extractTags(lower)],
        shouldCreateTask: false,
        shouldCreateReminder: false,
      );
    }

    // 2. Check for Commitments & Promises
    // Example: "I promised Sarah I would send her the document."
    if (RegExp(r'\b(promised|pledged|swore|i owe|committed to)\b').hasMatch(lower)) {
      final person = _extractPerson(trimmed);
      final dateResult = NlpDateParser.parse(trimmed);
      final title = _generateTitle(trimmed, prefixToRemove: ['i promised', 'promised to', 'committed to']);
      return ClassificationResult(
        title: title,
        memoryType: 'commitment',
        category: 'Commitments',
        tags: ['commitment', if (person != null) person.toLowerCase(), ..._extractTags(lower)],
        associatedPerson: person,
        associatedDate: dateResult.dateTime,
        shouldCreateTask: true,
        shouldCreateReminder: dateResult.dateTime != null,
        clarificationNeeded: dateResult.dateTime == null ? 'Would you like to set a deadline for this commitment?' : null,
      );
    }

    // 3. Check for Personal Preferences
    // Example: "I prefer doing important work early in the morning."
    if (RegExp(r'\b(prefer|my preference|i love|i hate|i dislike|my favorite|favourite|i always like)\b').hasMatch(lower)) {
      final title = _generateTitle(trimmed, prefixToRemove: ['i prefer', 'my preference is', 'i always like']);
      return ClassificationResult(
        title: title,
        memoryType: 'personal_preference',
        category: 'Personal',
        tags: ['preference', ..._extractTags(lower)],
        shouldCreateTask: false,
        shouldCreateReminder: false,
      );
    }

    // 4. Check for Important Dates / Expiry / Birthdays / Renewals
    // Example: "My laptop warranty expires in December."
    if (RegExp(r'\b(expires?|expiration|anniversary|birthday|renewal|due by|contract ends)\b').hasMatch(lower)) {
      final dateResult = NlpDateParser.parse(trimmed);
      final title = _generateTitle(trimmed);
      return ClassificationResult(
        title: title,
        memoryType: 'important_date',
        category: _detectCategory(lower, defaultCat: 'Personal'),
        tags: ['important_date', ..._extractTags(lower)],
        associatedDate: dateResult.dateTime,
        shouldCreateTask: false,
        shouldCreateReminder: dateResult.dateTime != null,
        clarificationNeeded: dateResult.dateTime == null ? 'Would you like to add a specific date or reminder for this?' : null,
      );
    }

    // 5. Check for Shopping / Purchase Intentions
    // Example: "I want to buy new headphones."
    if (RegExp(r'\b(want to buy|need to buy|purchase|pick up from store|groceries|shopping list)\b').hasMatch(lower)) {
      final title = _generateTitle(trimmed, prefixToRemove: ['want to buy', 'need to buy', 'buy']);
      return ClassificationResult(
        title: title,
        memoryType: 'shopping',
        category: 'Shopping',
        tags: ['shopping', ..._extractTags(lower)],
        shouldCreateTask: true,
        shouldCreateReminder: false,
      );
    }

    // 6. Check for Reference Information (passwords, accounts, links)
    if (RegExp(r'\b(password|pin code|license key|wifi|website|url|reference|account number)\b').hasMatch(lower)) {
      final title = _generateTitle(trimmed);
      return ClassificationResult(
        title: title,
        memoryType: 'reference',
        category: 'General',
        tags: ['reference', ..._extractTags(lower)],
        shouldCreateTask: false,
        shouldCreateReminder: false,
      );
    }

    // 7. Check for Tasks and Reminders
    // Example: "I need to call David tomorrow."
    final parsedDate = NlpDateParser.parse(trimmed);
    final hasTaskAction = RegExp(r'\b(need to|must|have to|call|email|send|finish|submit|clean|fix|schedule|buy|prepare|meeting with|meet with)\b').hasMatch(lower);
    final hasExplicitReminder = RegExp(r"\b(remind me|don'?t forget|alert me|notify me)\b").hasMatch(lower);

    if (hasExplicitReminder || (hasTaskAction && parsedDate.dateTime != null) || hasTaskAction) {
      final person = _extractPerson(trimmed);
      final title = _generateTitle(trimmed, prefixToRemove: [
        'remind me to',
        'remind me',
        'i need to',
        'need to',
        'i have to',
        'have to',
        "don't forget to",
        'dont forget to',
      ]);

      final isExplicitReminder = hasExplicitReminder || parsedDate.dateTime != null;

      return ClassificationResult(
        title: title,
        memoryType: isExplicitReminder ? 'reminder' : 'task',
        category: _detectCategory(lower, defaultCat: 'Work'),
        tags: [isExplicitReminder ? 'reminder' : 'task', if (person != null) person.toLowerCase(), ..._extractTags(lower)],
        associatedPerson: person,
        associatedDate: parsedDate.dateTime,
        recurrenceRule: parsedDate.recurrenceRule,
        shouldCreateTask: true,
        shouldCreateReminder: parsedDate.dateTime != null,
      );
    }

    // 8. General Note / Memory Fallback
    final person = _extractPerson(trimmed);
    final dateResult = NlpDateParser.parse(trimmed);

    return ClassificationResult(
      title: _generateTitle(trimmed),
      memoryType: 'general_note',
      category: _detectCategory(lower, defaultCat: 'General'),
      tags: [..._extractTags(lower), if (person != null) person.toLowerCase()],
      associatedPerson: person,
      associatedDate: dateResult.dateTime,
      shouldCreateTask: false,
      shouldCreateReminder: false,
    );
  }

  static String _generateTitle(String input, {List<String>? prefixToRemove}) {
    var text = input.trim();
    if (prefixToRemove != null) {
      for (final p in prefixToRemove) {
        if (text.toLowerCase().startsWith(p)) {
          text = text.substring(p.length).trim();
          break;
        }
      }
    }

    // Capitalize first letter
    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1);
    }

    // Limit length to ~60 characters if too long
    if (text.length > 60) {
      final cut = text.substring(0, 57);
      final lastSpace = cut.lastIndexOf(' ');
      if (lastSpace > 30) {
        return '${cut.substring(0, lastSpace)}...';
      }
      return '$cut...';
    }

    return text.isEmpty ? 'Untitled Note' : text;
  }

  static String? _extractPerson(String input) {
    // Matches: "call David", "with Sarah", "promised John", "told Michael"
    final match = RegExp(r'\b(?:call|with|promised|told|asked|email|meet|met)\s+([A-Z][a-z]+)\b').firstMatch(input);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  static String _detectCategory(String lower, {String defaultCat = 'General'}) {
    if (RegExp(r'\b(work|client|meeting|presentation|project|boss|office|deadline|report|code|app)\b').hasMatch(lower)) {
      return 'Work';
    }
    if (RegExp(r'\b(health|doctor|medicine|workout|exercise|dentist|gym|run|diet|hospital)\b').hasMatch(lower)) {
      return 'Health';
    }
    if (RegExp(r'\b(finance|bank|money|pay|bill|tax|invoice|salary|budget|invest)\b').hasMatch(lower)) {
      return 'Finance';
    }
    if (RegExp(r'\b(family|home|house|kids|mom|dad|wife|husband|car)\b').hasMatch(lower)) {
      return 'Personal';
    }
    return defaultCat;
  }

  static List<String> _extractTags(String lower) {
    final tags = <String>{};
    if (lower.contains('urgent') || lower.contains('asap')) tags.add('urgent');
    if (lower.contains('work')) tags.add('work');
    if (lower.contains('personal')) tags.add('personal');
    if (lower.contains('health')) tags.add('health');
    if (lower.contains('finance')) tags.add('finance');
    return tags.toList();
  }
}
