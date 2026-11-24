import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'speech_recognition_service.dart';

enum WakeWordListeningMode {
  inAppOnly,
  foregroundService,
}

class WakeWordService {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

  final ISpeechRecognitionService _speechService = SpeechToTextService();

  bool _isEnabled = false;
  WakeWordListeningMode _listeningMode = WakeWordListeningMode.inAppOnly;
  bool _isListeningForWakeWord = false;
  bool _isAssistantActive = false;
  Timer? _restartTimer;

  Function(String matchedPhrase, String? immediateQuery)? onWakeWordDetected;

  static const List<String> _wakeWords = [
    'hi kee',
    'hey kee',
    'hello kee',
    'ok kee',
    'kee',
  ];

  bool get isEnabled => _isEnabled;
  WakeWordListeningMode get listeningMode => _listeningMode;
  bool get isListeningForWakeWord => _isListeningForWakeWord;

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    if (enabled) {
      await startWakeWordMonitoring();
    } else {
      await stopWakeWordMonitoring();
    }
  }

  void setListeningMode(WakeWordListeningMode mode) {
    _listeningMode = mode;
  }

  /// Inform the wake word engine whether an active assistant session is running
  /// so it doesn't collide with the conversation's speech recognition.
  void setAssistantActive(bool active) {
    _isAssistantActive = active;
    if (active) {
      stopWakeWordMonitoring(isTemporary: true);
    } else {
      if (_isEnabled) {
        // Delay slightly before resuming wake word loop to prevent mic state races
        _restartTimer?.cancel();
        _restartTimer = Timer(const Duration(milliseconds: 700), () {
          startWakeWordMonitoring();
        });
      }
    }
  }

  Future<void> startWakeWordMonitoring() async {
    if (!_isEnabled || _isAssistantActive || _isListeningForWakeWord) return;

    try {
      final hasPermission = await _speechService.initialize();
      if (!hasPermission) {
        debugPrint('[WakeWordService] Microphone permission not available for wake word');
        return;
      }

      _isListeningForWakeWord = true;

      await _speechService.startListening(
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
        onResult: (text, isFinal) {
          _analyzeSpokenText(text);
        },
      );
    } catch (e) {
      _isListeningForWakeWord = false;
      debugPrint('[WakeWordService] Error starting wake word listening: $e');
      _scheduleRestart();
    }
  }

  void _analyzeSpokenText(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return;

    for (final wakeWord in _wakeWords) {
      if (lower.contains(wakeWord)) {
        // Found wake word! Extract any subsequent query uttered in the same breath
        final index = lower.indexOf(wakeWord);
        String? immediateQuery;
        final remainder = lower.substring(index + wakeWord.length).trim();
        if (remainder.isNotEmpty) {
          immediateQuery = remainder;
        }

        debugPrint('[WakeWordService] Wake word detected: "$wakeWord" (query: "$immediateQuery")');
        _triggerActivation(wakeWord, immediateQuery);
        return;
      }
    }
  }

  void _triggerActivation(String wakeWord, String? immediateQuery) {
    // Provide instant subtle physical haptic feedback
    HapticFeedback.mediumImpact();

    // Stop wake word listening
    stopWakeWordMonitoring(isTemporary: true);

    // Notify listeners / assistant controller
    onWakeWordDetected?.call(wakeWord, immediateQuery);
  }

  Future<void> stopWakeWordMonitoring({bool isTemporary = false}) async {
    _restartTimer?.cancel();
    _isListeningForWakeWord = false;
    if (!isTemporary) {
      _isEnabled = false;
    }
    await _speechService.stopListening();
  }

  void _scheduleRestart() {
    if (!_isEnabled || _isAssistantActive) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(seconds: 2), () {
      if (_isEnabled && !_isAssistantActive) {
        startWakeWordMonitoring();
      }
    });
  }

  void dispose() {
    _restartTimer?.cancel();
    _speechService.stopListening();
  }
}
