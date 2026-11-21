# Kee — Knowledge Extension Entity

> **Your memory. Extended.**

**Kee** (K.E.E. · Knowledge Extension Entity) is a personal AI memory and intelligence assistant built with Flutter.

*"Meet Kee, your Knowledge Extension Entity. A personal intelligence that helps you capture what matters, remember what you forget, and retrieve information whenever you need it."*

---

## Brand Identity & Philosophy

- **Name:** Kee
- **Full Identity:** K.E.E.
- **Meaning:** Knowledge Extension Entity
- **Tagline:** Your memory. Extended.
- **Aesthetic:** Inspired by NØVARÉ minimalism — architectural obsidian (`#050505`) and warm champagne ivory linen (`#FBF2E6`). Serious, refined, personal technology.

Kee is designed as a direct cognitive extension of the user. Rather than an external chatbot or a generic cloud assistant, Kee serves as a private, on-device intelligence layer that ensures what matters to you is captured accurately, remembered reliably, and recalled effortlessly.

---

## Core Capabilities

1. **Capture What Matters**:
   - Frictionless quick-capture for thoughts, tasks, ideas, preferences, commitments, and voice notes.
   - Live deterministic intent classification (Task, Reminder, Idea, Commitment, Preference, Date, Shopping, Reference).
   - Protects creative ideas from being converted into false tasks.

2. **Remember What You Forget**:
   - Deterministic NLP date parsing: relative, recurring, and natural-language deadlines (*"tomorrow"*, *"next Friday"*, *"every Monday at 9am"*).
   - Offline local notifications (`flutter_local_notifications`) that fire reliably without network connectivity.

3. **Natural Offline Recall ("Ask Kee")**:
   - Conversational recall grounded strictly in your personal records.
   - Zero hallucination guarantee: retrieves verified memories and highlights tap-to-view source citations.

4. **100% Local-First & Private**:
   - On-device SQLite persistence (`sqflite`).
   - No paid cloud AI dependencies, no telemetry, no tracking, and no subscriptions.

5. **Adaptive Design System**:
   - Dual theme system: Pure Obsidian Dark and Warm Alabaster Light.
   - Full semantic `Theme.of(context)` styling with zero hardcoded colors.

---

## Running the Application

### 1. Web Browser Preview (Edge / Chrome)
```bash
# Instant local web preview
python3 -m http.server 8080 --directory build/web

# Or live Flutter dev mode
flutter run -d chrome
```

### 2. Physical Android Device
```bash
# Verify device
adb devices

# Run in debug mode
flutter run
```

### 3. Build APK
```bash
flutter build apk --debug
```

---

## Architecture

- **`lib/core/`**: Intelligence layer (deterministic classification, date parsing, recall engine), SQLite database, notifications, and theme providers.
- **`lib/features/`**: Feature-driven modules (capture, home, memories, reminders, recall, settings).
- **`lib/core/widgets/`**: Reusable UI components including the official `KeeLogo` and `KeeOnboardingSheet`.
