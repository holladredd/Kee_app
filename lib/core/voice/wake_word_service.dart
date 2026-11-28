import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'speech_recognition_service.dart';

enum WakeWordListeningMode { inAppOnly, foregroundService }

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
  DateTime? _lastActivationAt;
  static const Duration _activationCooldown = Duration(milliseconds: 2500);

  Function(String matchedPhrase, String? immediateQuery)? onWakeWordDetected;

  static const List<String> _wakeWords = ['hi kee'];

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

    // Web browsers do not support continuous background microphone listening
    // and only permit a single SpeechRecognition instance at a time.
    // We disable background wake-word polling on web to prevent InvalidStateError
    // collisions with the active voice assistant.
    if (kIsWeb) {
      debugPrint(
        '[WakeWordService] Background wake-word monitoring is disabled on web.',
      );
      return;
    }

    try {
      final hasPermission = await _speechService.initialize();
      if (!hasPermission) {
        debugPrint(
          '[WakeWordService] Microphone permission not available for wake word',
        );
        return;
      }

      _isListeningForWakeWord = true;

      await _speechService.startListening(
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
        onResult: (text, isFinal) {
          _analyzeSpokenText(text, isFinal);
        },
      );
    } catch (e) {
      _isListeningForWakeWord = false;
      debugPrint('[WakeWordService] Error starting wake word listening: $e');
      _scheduleRestart();
    }
  }

  void _analyzeSpokenText(String text, bool isFinal) {
    // Only activate on confirmed final recognition results to prevent partial false triggers
    if (!isFinal || _isAssistantActive) return;

    final now = DateTime.now();
    if (_lastActivationAt != null &&
        now.difference(_lastActivationAt!) < _activationCooldown) {
      return;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    for (final wakeWord in _wakeWords) {
      final match = RegExp(
        '\\b${RegExp.escape(wakeWord)}\\b',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null) {
        _lastActivationAt = now;
        String? immediateQuery;
        final remainder = trimmed
            .substring(match.end)
            .replaceFirst(RegExp(r'^[,\s!]+'), '')
            .trim();
        if (remainder.isNotEmpty) {
          immediateQuery = remainder;
        }

        debugPrint(
          '[WakeWordService] Wake word detected: "$wakeWord" (query: "$immediateQuery")',
        );
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
