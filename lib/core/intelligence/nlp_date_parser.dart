class ParsedDateResult {
  final DateTime? dateTime;
  final String? recurrenceRule; // daily, weekly, monthly, yearly, custom:N_days
  final bool hasExplicitTime;
  final String cleanedText; // text with date keywords removed

  ParsedDateResult({
    this.dateTime,
    this.recurrenceRule,
    this.hasExplicitTime = false,
    required this.cleanedText,
  });
}

class NlpDateParser {
  NlpDateParser._();

  static ParsedDateResult parse(String input, {DateTime? referenceTime}) {
    final now = referenceTime ?? DateTime.now();
    final lower = input.toLowerCase().trim();

    DateTime? targetDate;
    String? recurrence;
    bool hasTime = false;
    String cleaned = input;

    // Check Recurrence First
    if (RegExp(r'\bevery\s+day\b|\bdaily\b').hasMatch(lower)) {
      recurrence = 'daily';
      targetDate = DateTime(now.year, now.month, now.day + 1, 9, 0);
    } else if (RegExp(r'\bevery\s+week\b|\bweekly\b').hasMatch(lower)) {
      recurrence = 'weekly';
      targetDate = DateTime(now.year, now.month, now.day + 7, 9, 0);
    } else if (RegExp(r'\bevery\s+month\b|\bmonthly\b').hasMatch(lower)) {
      recurrence = 'monthly';
      targetDate = DateTime(now.year, now.month + 1, now.day, 9, 0);
    } else if (RegExp(r'\bevery\s+year\b|\byearly\b|\bannually\b').hasMatch(lower)) {
      recurrence = 'yearly';
      targetDate = DateTime(now.year + 1, now.month, now.day, 9, 0);
    } else {
      final customDaysMatch = RegExp(r'\bevery\s+(\d+)\s+days?\b').firstMatch(lower);
      if (customDaysMatch != null) {
        final days = int.tryParse(customDaysMatch.group(1)!) ?? 1;
        recurrence = 'custom:$days';
        targetDate = now.add(Duration(days: days));
      }
      final customWeekdayMatch = RegExp(r'\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b').firstMatch(lower);
      if (customWeekdayMatch != null) {
        recurrence = 'weekly';
        targetDate = _nextWeekday(now, _weekdayFromName(customWeekdayMatch.group(1)!));
      }
    }

    // Check Relative Time expressions (minutes / hours)
    final inMinutesMatch = RegExp(r'\bin\s+(\d+)\s+min(?:ute)?s?\b').firstMatch(lower);
    if (inMinutesMatch != null) {
      final mins = int.tryParse(inMinutesMatch.group(1)!) ?? 10;
      targetDate = now.add(Duration(minutes: mins));
      hasTime = true;
    }

    final inHoursMatch = RegExp(r'\bin\s+(\d+)\s+hours?\b').firstMatch(lower);
    if (inHoursMatch != null) {
      final hrs = int.tryParse(inHoursMatch.group(1)!) ?? 1;
      targetDate = now.add(Duration(hours: hrs));
      hasTime = true;
    }

    // Days relative
    if (targetDate == null) {
      if (lower.contains('today')) {
        targetDate = DateTime(now.year, now.month, now.day, 18, 0);
      } else if (lower.contains('tomorrow')) {
        targetDate = DateTime(now.year, now.month, now.day + 1, 9, 0);
      } else if (lower.contains('day after tomorrow')) {
        targetDate = DateTime(now.year, now.month, now.day + 2, 9, 0);
      } else if (lower.contains('this evening') || lower.contains('tonight')) {
        targetDate = DateTime(now.year, now.month, now.day, 19, 0);
        hasTime = true;
      } else if (lower.contains('in two weeks') || lower.contains('in 2 weeks')) {
        targetDate = now.add(const Duration(days: 14));
      } else if (lower.contains('next week')) {
        targetDate = now.add(const Duration(days: 7));
      } else if (lower.contains('next month')) {
        targetDate = DateTime(now.year, now.month + 1, 1, 9, 0);
      } else if (lower.contains('end of the month') || lower.contains('end of month')) {
        final lastDay = DateTime(now.year, now.month + 1, 0);
        targetDate = DateTime(lastDay.year, lastDay.month, lastDay.day, 18, 0);
      } else {
        // Next specific weekday (e.g. next friday, next monday)
        final nextWeekdayMatch = RegExp(r'\b(?:next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b').firstMatch(lower);
        if (nextWeekdayMatch != null) {
          final dayName = nextWeekdayMatch.group(1)!;
          final targetWk = _weekdayFromName(dayName);
          targetDate = _nextWeekday(now, targetWk);
        }
      }
    }

    // Check specific month name mentions (e.g. "in December", "December 15")
    if (targetDate == null) {
      final monthMatch = RegExp(r'\b(?:in\s+)?(january|february|march|april|may|june|july|august|september|october|november|december)(?:\s+(\d{1,2}))?\b').firstMatch(lower);
      if (monthMatch != null) {
        final mName = monthMatch.group(1)!;
        final mDay = monthMatch.group(2) != null ? int.tryParse(monthMatch.group(2)!) ?? 1 : 1;
        final mNum = _monthFromName(mName);
        var year = now.year;
        if (mNum < now.month || (mNum == now.month && mDay < now.day)) {
          year++;
        }
        targetDate = DateTime(year, mNum, mDay, 9, 0);
      }
    }

    // Check explicit time expressions (e.g. at 5pm, at 14:30, at 8:00 AM)
    final timeMatch = RegExp(r'\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b').firstMatch(lower);
    if (timeMatch != null && targetDate != null) {
      var hour = int.tryParse(timeMatch.group(1)!) ?? 9;
      final minute = timeMatch.group(2) != null ? int.tryParse(timeMatch.group(2)!) ?? 0 : 0;
      final meridiem = timeMatch.group(3);

      if (meridiem == 'pm' && hour < 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;

      targetDate = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);
      hasTime = true;
    }

    return ParsedDateResult(
      dateTime: targetDate,
      recurrenceRule: recurrence,
      hasExplicitTime: hasTime,
      cleanedText: cleaned,
    );
  }

  static int _weekdayFromName(String name) {
    switch (name) {
      case 'monday': return DateTime.monday;
      case 'tuesday': return DateTime.tuesday;
      case 'wednesday': return DateTime.wednesday;
      case 'thursday': return DateTime.thursday;
      case 'friday': return DateTime.friday;
      case 'saturday': return DateTime.saturday;
      case 'sunday': return DateTime.sunday;
      default: return DateTime.monday;
    }
  }

  static DateTime _nextWeekday(DateTime from, int targetWeekday) {
    int daysToAdd = targetWeekday - from.weekday;
    if (daysToAdd <= 0) daysToAdd += 7;
    return DateTime(from.year, from.month, from.day + daysToAdd, 9, 0);
  }

  static int _monthFromName(String name) {
    switch (name) {
      case 'january': return 1;
      case 'february': return 2;
      case 'march': return 3;
      case 'april': return 4;
      case 'may': return 5;
      case 'june': return 6;
      case 'july': return 7;
      case 'august': return 8;
      case 'september': return 9;
      case 'october': return 10;
      case 'november': return 11;
      case 'december': return 12;
      default: return 1;
    }
  }
}
