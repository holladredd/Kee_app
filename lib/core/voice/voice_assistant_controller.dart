import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../intelligence/conversation_provider.dart';
import '../intelligence/unified_chat_provider.dart';
import 'assistant_state.dart';
import 'native_voice_bridge.dart';
import 'speech_recognition_service.dart';
import 'text_to_speech_service.dart';
import 'wake_word_service.dart';

final ttsServiceProvider = Provider<ITextToSpeechService>((ref) {
  return FlutterTtsService();
});

final speechRecognitionServiceProvider = Provider<ISpeechRecognitionService>((
  ref,
) {
  return SpeechToTextService();
});

final wakeWordServiceProvider = Provider<WakeWordService>((ref) {
  return WakeWordService();
});

final voiceAssistantProvider =
    NotifierProvider<VoiceAssistantController, VoiceAssistantState>(() {
      return VoiceAssistantController();
    });

class VoiceAssistantController extends Notifier<VoiceAssistantState> {
  late final ITextToSpeechService _tts;
  late final ISpeechRecognitionService _speech;
  late final WakeWordService _wakeWord;

  Timer? _silenceTimer;
  Timer? _continuousTurnTimer;
  Timer? _errorRecoveryTimer;
  bool _hasDispatchedFinalForTurn = false;

  @override
  VoiceAssistantState build() {
    _tts = ref.read(ttsServiceProvider);
    _speech = ref.read(speechRecognitionServiceProvider);
    _wakeWord = ref.read(wakeWordServiceProvider);

    _initializeServices();

    return const VoiceAssistantState();
  }

  void _initializeServices() {
    // Restore persisted hands-free preference on Android and auto-start the
    // background wake-word service.  With the new default of true, first-launch
    // users get hands-free automatically.  An explicit user disable (false in
    // SharedPreferences) is still respected.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      Future.microtask(() async {
        try {
          final bridge = ref.read(nativeVoiceBridgeProvider);
          final enabled = await bridge.getPersistedHandsFree();
          state = state.copyWith(isHandsFreeEnabled: enabled);
          if (enabled) {
            final running = await bridge.isServiceRunning();
            if (!running) {
              // Check if the Vosk model is already downloaded — only auto-start
              // the foreground service when the model is ready so we don't hit
              // a half-initialised state on first launch (the setup dialog will
              // handle download when the user first visits Settings or taps the
              // mic).
              final modelReady = await bridge.isWakeWordModelReady();
              if (modelReady) {
                await bridge.startBackgroundListening();
              }
            }
          }
        } catch (e) {
          debugPrint('[VoiceAssistantController] Restore hands-free error: $e');
        }
      });
    }

    // Connect wake word activation handler
    _wakeWord.onWakeWordDetected = (phrase, trailingQuery) {
      handleWakeWordActivation(trailingQuery);
    };

    // Initialize Speech Error Handling
    final speech = _speech;
    if (speech is SpeechToTextService) {
      speech.onError = (err) {
        final lower = err.toLowerCase();
        if (lower.contains('no-speech') || lower.contains('aborted')) {
          // If silence detected, gracefully return to idle rather than showing a red error
          if (state.isListening && state.liveTranscript.isEmpty) {
            state = state.copyWith(state: AssistantState.idle, soundLevel: 0.0);
          }
          return;
        }

        String friendlyMessage;
        if (lower.contains('network')) {
          friendlyMessage = kIsWeb
              ? 'Web speech requires cloud STT access. Please verify your connection or type below.'
              : 'Voice recognition network error. Please check your connection.';
        } else if (lower.contains('not-allowed') ||
            lower.contains('permission')) {
          friendlyMessage =
              'Microphone permission denied. Allow mic access in your browser or device settings.';
        } else {
          friendlyMessage = 'Speech recognition notice: $err';
        }

        _handleError(friendlyMessage);
      };
    }

    // Initialize TTS
    final tts = _tts;
    if (tts is FlutterTtsService) {
      tts.onCompletion = () {
        _onTtsCompleted();
      };
      tts.onCancel = () {
        debugPrint('[VoiceAssistantController] TTS cancelled/interrupted');
      };
      tts.onError = (err) {
        _handleError('Speech output notice: $err');
      };
    }
  }

  void _handleError(String message) {
    _silenceTimer?.cancel();
    _continuousTurnTimer?.cancel();
    _errorRecoveryTimer?.cancel();

    state = state.copyWith(
      state: AssistantState.error,
      errorMessage: message,
      soundLevel: 0.0,
    );
    _wakeWord.setAssistantActive(false);

    // Resume native Vosk after error so wake-word detection isn't left disabled
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        state.isHandsFreeEnabled) {
      try {
        final bridge = ref.read(nativeVoiceBridgeProvider);
        bridge.resumeWakeWord();
      } catch (_) {}
    }

    // Auto-recover after 4 seconds so the assistant UI is never permanently blocked
    _errorRecoveryTimer = Timer(const Duration(seconds: 4), () {
      if (state.state == AssistantState.error) {
        state = state.copyWith(state: AssistantState.idle, errorMessage: null);
      }
    });
  }

  void clearError() {
    _errorRecoveryTimer?.cancel();
    state = state.copyWith(
      state: AssistantState.idle,
      errorMessage: null,
      soundLevel: 0.0,
    );
  }

  /// Triggered when the wake word "Hi Kee" is recognized locally on-device
  Future<void> handleWakeWordActivation(String? immediateQuery) async {
    HapticFeedback.heavyImpact();

    state = state.copyWith(
      state: AssistantState.listening,
      isExpanded: true,
      liveTranscript: immediateQuery ?? '',
      errorMessage: null,
    );

    _wakeWord.setAssistantActive(true);

    if (immediateQuery != null && immediateQuery.trim().isNotEmpty) {
      // User said "Hi Kee <query>" in one breath
      await processSpokenInput(immediateQuery);
    } else {
      // Normal wake: prompt or immediately listen
      await startListening();
    }
  }

  /// Start listening for user speech
  Future<void> startListening() async {
    _silenceTimer?.cancel();
    _continuousTurnTimer?.cancel();
    _hasDispatchedFinalForTurn = false;

    // If currently speaking, stop TTS first
    if (state.isSpeaking) {
      await _tts.stop();
    }

    state = state.copyWith(
      state: AssistantState.listening,
      liveTranscript: '',
      errorMessage: null,
      soundLevel: 0.0,
    );

    _wakeWord.setAssistantActive(true);

    // Pause native Vosk wake-word listener before Flutter grabs the mic
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        state.isHandsFreeEnabled) {
      try {
        final bridge = ref.read(nativeVoiceBridgeProvider);
        await bridge.pauseWakeWord();
      } catch (e) {
        debugPrint('[VoiceAssistantController] pauseWakeWord error: $e');
      }
    }

    try {
      await _speech.startListening(
        listenFor: const Duration(seconds: 25),
        pauseFor: const Duration(seconds: 3),
        onSoundLevel: (level) {
          if (state.isListening) {
            state = state.copyWith(soundLevel: level);
          }
        },
        onResult: (text, isFinal) {
          // Ignore stale callbacks if session already moved to processing/idle
          if (!state.isListening && !state.isInterrupted) return;

          state = state.copyWith(liveTranscript: text);

          if (isFinal &&
              text.trim().isNotEmpty &&
              !_hasDispatchedFinalForTurn) {
            _hasDispatchedFinalForTurn = true;
            _continuousTurnTimer?.cancel();
            processSpokenInput(text);
          }
        },
      );
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('InvalidStateError') ||
          msg.contains('already started')) {
        msg = 'Microphone was resetting. Please tap again.';
      } else if (msg.contains('not initialized') ||
          msg.contains('permission')) {
        msg = kIsWeb
            ? 'Please allow microphone access in your browser.'
            : 'Microphone permission required.';
      }
      _handleError(msg);
    }
  }

  /// Instant interruption: instantly cuts off TTS and transitions immediately back to listening
  Future<void> interrupt() async {
    HapticFeedback.lightImpact();
    debugPrint('[VoiceAssistantController] Interruption triggered!');

    _continuousTurnTimer?.cancel();
    await _tts.stop();

    state = state.copyWith(
      state: AssistantState.interrupted,
      liveTranscript: '',
      soundLevel: 0.0,
    );

    // Transition smoothly back to listening
    await Future.delayed(const Duration(milliseconds: 150));
    await startListening();
  }

  /// Process the captured voice utterance through Kee's central intelligence engine
  Future<void> processSpokenInput(String rawText) async {
    final query = rawText.trim();
    if (query.isEmpty) {
      await startListening();
      return;
    }

    _silenceTimer?.cancel();
    await _speech.stopListening();

    state = state.copyWith(
      state: AssistantState.processing,
      liveTranscript: query,
      soundLevel: 0.0,
    );

    try {
      final engine = ref.read(conversationEngineProvider);
      final action = await engine.processMessage(query);

      final reply = action.responseText;

      // Automatically add to the single unified chat thread
      try {
        ref
            .read(unifiedChatProvider.notifier)
            .recordVoiceTurn(
              userText: query,
              assistantText: reply,
              intent: action.intent,
              savedMemory: action.savedMemory,
              scheduledReminder: action.scheduledReminder,
              savedTask: action.savedTask,
              citations: action.citedMemories,
              citedReminders: action.citedReminders,
              citedTasks: action.citedTasks,
            );
      } catch (e) {
        debugPrint(
          '[VoiceAssistantController] Failed to record in unified chat: $e',
        );
      }

      state = state.copyWith(
        state: AssistantState.speaking,
        lastAssistantResponse: reply,
      );

      await _tts.speak(reply);
    } catch (e) {
      _handleError('Could not process request: $e');
    }
  }

  /// Called when TTS finishes speaking the assistant's reply
  void _onTtsCompleted() {
    if (!state.isSpeaking) return;

    // One-shot mode (default): end the voice session cleanly without reopening the mic
    if (!state.isContinuousMode) {
      dismissSession();
      return;
    }

    // Intentional continuous conversation mode: open one follow-up listening turn
    // with a hard 7-second turn timeout that is NOT defeated by partial ambient noise.
    startListening();

    _continuousTurnTimer?.cancel();
    _continuousTurnTimer = Timer(const Duration(seconds: 7), () {
      if (state.isListening && !_hasDispatchedFinalForTurn) {
        dismissSession();
      }
    });
  }

  /// Toggle intentional continuous conversation mode
  void setContinuousMode(bool enabled) {
    state = state.copyWith(isContinuousMode: enabled);
  }

  /// Dismiss the active voice session and return to idle
  Future<void> dismissSession() async {
    _silenceTimer?.cancel();
    _continuousTurnTimer?.cancel();
    _errorRecoveryTimer?.cancel();

    await _speech.stopListening();
    await _tts.stop();

    state = state.copyWith(
      state: AssistantState.idle,
      liveTranscript: '',
      soundLevel: 0.0,
      errorMessage: null,
      isExpanded: false,
    );

    _wakeWord.setAssistantActive(false);

    // Resume native Vosk wake-word listener now that Flutter released the mic
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        state.isHandsFreeEnabled) {
      try {
        final bridge = ref.read(nativeVoiceBridgeProvider);
        await bridge.resumeWakeWord();
      } catch (e) {
        debugPrint('[VoiceAssistantController] resumeWakeWord error: $e');
      }
    }
  }

  /// Toggle hands-free wake word detection
  Future<void> toggleHandsFree(bool enabled) async {
    state = state.copyWith(isHandsFreeEnabled: enabled);

    try {
      final bridge = ref.read(nativeVoiceBridgeProvider);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // On Android, the native KeeBackgroundVoiceService handles wake-word
        // detection and floating overlay; skip Dart-side WakeWordService to
        // avoid microphone collision.
        await _wakeWord.setEnabled(false);
        if (enabled) {
          await bridge.startBackgroundListening();
        } else {
          await bridge.stopBackgroundListening();
        }
        return;
      }
    } catch (e) {
      debugPrint(
        '[VoiceAssistantController] Native background toggle error: $e',
      );
    }

    await _wakeWord.setEnabled(enabled);
  }

  /// Set speech rate (0.1 to 1.0)
  Future<void> setSpeechRate(double rate) async {
    final clamped = rate.clamp(0.2, 1.0);
    state = state.copyWith(speechRate: clamped);
    await _tts.setSpeechRate(clamped);
  }

  /// Set speech pitch (0.5 to 2.0)
  Future<void> setSpeechPitch(double pitch) async {
    final clamped = pitch.clamp(0.5, 2.0);
    state = state.copyWith(speechPitch: clamped);
    await _tts.setPitch(clamped);
  }

  /// Toggle assistant expansion between compact floating widget and full overlay
  void setExpanded(bool expanded) {
    state = state.copyWith(isExpanded: expanded);
  }

  /// Speak a test sentence for settings preview
  Future<void> testVoiceOutput() async {
    state = state.copyWith(state: AssistantState.speaking);
    await _tts.speak(
      'Hi, I am Kee. Your Knowledge Extension Entity. How can I help you today?',
    );
  }
}
