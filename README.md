# Kee Mobile Application (Android-First)

**Kee** is an Android-first personal memory and task assistant built with Flutter.

> *"Tell Kee anything. It remembers. Ask Kee anything. It recalls."*

---

## Key Features

1. **Quick Capture**:
   - Save thoughts, tasks, ideas, preferences, or promises in seconds.
   - Live intelligent classification preview that automatically identifies the intent (Task, Reminder, Idea, Commitment, Preference, Date, Shopping, Reference).
   - Distinguishes ideas from tasks (never creates false reminders for creative ideas).
2. **Offline-First SQLite Persistence**:
   - All memories, tasks, and reminders are saved locally in SQLite (`sqflite`).
   - Works 100% offline without needing any cloud API or backend server.
3. **Deterministic NLP Date Parsing & Local Reminders**:
   - Parses natural expressions: *"tomorrow"*, *"next Friday"*, *"in 2 weeks"*, *"at the end of the month"*, *"every Monday"*, *"every 3 days"*.
   - Uses local Android notifications (`flutter_local_notifications`) for alarms and reminders that fire even when offline.
4. **Conversational Recall ("Ask Kee")**:
   - Grounded retrieval-first assistant that searches your local records and answers queries without hallucination.
   - Shows tap-to-view source citations for retrieved memories.
5. **Dark Mode & Design System**:
   - Complete light and dark themes using semantic `Theme.of(context)` styling.
   - Clean Material 3 design with accessible spacing and typography.
6. **Voice Input**:
   - On-device speech-to-text with review-and-edit workflow before saving.
7. **Zero Monetization or Paid AI Dependencies**:
   - Genuinely free product: no advertisements, no subscriptions, no cloud AI limits or mandatory accounts.

---

## Running on your Physical Android Device

### Prerequisites:
1. Turn on **Developer Options** and enable **USB Debugging** on your Android phone.
2. Connect your phone via USB and allow debugging permissions when prompted on the screen.

### 1. Verify Connected Device
```bash
adb devices
```

### 2. Run Directly on Phone
```bash
flutter run
```

### 3. Build Debug APK
If you want to generate an installable APK file directly:
```bash
flutter build apk --debug
```
The APK will be generated at:
`build/app/outputs/flutter-apk/app-debug.apk`

---

## Architecture

- **State Management**: Riverpod (`flutter_riverpod`)
- **Navigation**: GoRouter (`go_router`) with StatefulShellRoute for Bottom Navigation
- **Local Database**: SQLite (`sqflite`)
- **Local Notifications**: `flutter_local_notifications`
- **Audio / Speech**: `speech_to_text`
- **Data Layer**: Clean Repository pattern with outbox sync queue support
