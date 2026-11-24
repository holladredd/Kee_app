import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../intelligence/conversation_provider.dart';
import '../intelligence/unified_chat_provider.dart';
import 'assistant_state.dart';
import 'speech_recognition_service.dart';
import 'text_to_speech_service.dart';
import 'wake_word_service.dart';

final ttsServiceProvider = Provider<ITextToSpeechService>((ref) {
  return FlutterTtsService();
});

final speechRecognitionServiceProvider = Provider<ISpeechRecognitionService>((ref) {
  return SpeechToTextService();
});

final wakeWordServiceProvider = Provider<WakeWordService>((ref) {
  return WakeWordService();
});

final voiceAssistantProvider = NotifierProvider<VoiceAssistantController, VoiceAssistantState>(() {
  return VoiceAssistantController();
});

class VoiceAssistantController extends Notifier<VoiceAssistantState> {
  late final ITextToSpeechService _tts;
  late final ISpeechRecognitionService _speech;
  late final WakeWordService _wakeWord;

  Timer? _silenceTimer;
  Timer? _continuousTurnTimer;

  @override
  VoiceAssistantState build() {
    _tts = ref.read(ttsServiceProvider);
    _speech = ref.read(speechRecognitionServiceProvider);
    _wakeWord = ref.read(wakeWordServiceProvider);

    _initializeServices();

    return const VoiceAssistantState();
  }

  void _initializeServices() {
    // Connect wake word activation handler
    _wakeWord.onWakeWordDetected = (phrase, trailingQuery) {
      handleWakeWordActivation(trailingQuery);
    };

    // Initialize TTS
    if (_tts is FlutterTtsService) {
      final flutterTts = _tts;
      flutterTts.onCompletion = () {
        _onTtsCompleted();
      };
      flutterTts.onCancel = () {
        debugPrint('[VoiceAssistantController] TTS cancelled/interrupted');
      };
      flutterTts.onError = (err) {
        state = state.copyWith(
          state: AssistantState.error,
          errorMessage: 'Speech output error: $err',
        );
      };
    }
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

    // If currently speaking, stop TTS first
    if (state.isSpeaking) {
      await _tts.stop();
    }

    state = state.copyWith(
      state: AssistantState.listening,
      errorMessage: null,
      soundLevel: 0.0,
    );

    _wakeWord.setAssistantActive(true);

    try {
      await _speech.startListening(
        listenFor: const Duration(seconds: 25),
        pauseFor: const Duration(seconds: 3),
        onSoundLevel: (level) {
          state = state.copyWith(soundLevel: level);
        },
        onResult: (text, isFinal) {
          state = state.copyWith(liveTranscript: text);

          if (isFinal && text.trim().isNotEmpty) {
            processSpokenInput(text);
          }
        },
      );
    } catch (e) {
      state = state.copyWith(
        state: AssistantState.error,
        errorMessage: 'Microphone input error: $e',
      );
      _wakeWord.setAssistantActive(false);
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
        ref.read(unifiedChatProvider.notifier).recordVoiceTurn(
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
        debugPrint('[VoiceAssistantController] Failed to record in unified chat: $e');
      }

      state = state.copyWith(
        state: AssistantState.speaking,
        lastAssistantResponse: reply,
      );

      await _tts.speak(reply);
    } catch (e) {
      state = state.copyWith(
        state: AssistantState.error,
        errorMessage: 'Intelligence processing error: $e',
      );
      _wakeWord.setAssistantActive(false);
    }
  }

  /// Called when TTS finishes speaking the assistant's reply
  void _onTtsCompleted() {
    if (!state.isSpeaking) return;

    // Transition back to listening for continuous natural conversation turns!
    state = state.copyWith(
      state: AssistantState.listening,
      soundLevel: 0.0,
    );

    // Auto-listen for next turn
    startListening();

    // If no follow-up speech is detected after 7 seconds, transition gracefully to idle
    _continuousTurnTimer?.cancel();
    _continuousTurnTimer = Timer(const Duration(seconds: 7), () {
      if (state.isListening && state.liveTranscript.isEmpty) {
        dismissSession();
      }
    });
  }

  /// Dismiss the active voice session and return to idle
  Future<void> dismissSession() async {
    _silenceTimer?.cancel();
    _continuousTurnTimer?.cancel();

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
  }

  /// Toggle hands-free wake word detection
  Future<void> toggleHandsFree(bool enabled) async {
    state = state.copyWith(isHandsFreeEnabled: enabled);
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
    await _tts.speak('Hi, I am Kee. Your Knowledge Extension Entity. How can I help you today?');
  }
}
