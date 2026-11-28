import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kee/core/database/database_helper.dart';
import 'package:kee/core/intelligence/conversation_provider.dart';
import 'package:kee/core/intelligence/kee_conversation_engine.dart';
import 'package:kee/core/intelligence/recall_engine.dart';
import 'package:kee/core/notifications/notification_service.dart';
import 'package:kee/core/voice/assistant_state.dart';
import 'package:kee/core/voice/native_voice_bridge.dart';
import 'package:kee/core/voice/speech_recognition_service.dart';
import 'package:kee/core/voice/text_to_speech_service.dart';
import 'package:kee/core/voice/voice_assistant_controller.dart';
import 'package:kee/features/capture/presentation/voice_capture_dialog.dart';
import 'package:kee/features/memories/data/memory_model.dart';
import 'package:kee/features/memories/data/memory_repository.dart';
import 'package:kee/features/reminders/data/reminder_model.dart';
import 'package:kee/features/reminders/data/reminder_repository.dart';
import 'package:kee/features/reminders/data/task_model.dart';

class _FakeMemoryRepository extends MemoryRepository {
  _FakeMemoryRepository() : super(DatabaseHelper.instance);

  @override
  Future<List<MemoryModel>> getAllMemories({
    String? category,
    String? query,
    bool includeDeleted = false,
  }) async => [];
}

class _FakeReminderRepository extends ReminderRepository {
  _FakeReminderRepository()
    : super(DatabaseHelper.instance, NotificationService.instance);

  @override
  Future<List<ReminderModel>> getReminders({bool activeOnly = false}) async =>
      [];

  @override
  Future<List<TaskModel>> getTasks({String? status}) async => [];
}

class _FakeNativeVoiceBridge implements NativeVoiceBridge {
  final List<String> events = [];
  bool persistedHandsFree = true;
  bool serviceRunning = false;
  int startBackgroundCalls = 0;
  int stopBackgroundCalls = 0;
  int pauseWakeWordCalls = 0;
  int resumeWakeWordCalls = 0;
  Completer<void>? pauseCompleter;

  @override
  void initialize() {}

  @override
  Future<bool> getPersistedHandsFree() async => persistedHandsFree;

  @override
  Future<bool> isServiceRunning() async => serviceRunning;

  @override
  Future<bool> startBackgroundListening() async {
    startBackgroundCalls++;
    events.add('bridge.startBackgroundListening');
    serviceRunning = true;
    return true;
  }

  @override
  Future<bool> stopBackgroundListening() async {
    stopBackgroundCalls++;
    events.add('bridge.stopBackgroundListening');
    serviceRunning = false;
    return true;
  }

  @override
  Future<void> pauseWakeWord() async {
    pauseWakeWordCalls++;
    events.add('bridge.pauseWakeWord');
    if (pauseCompleter != null) {
      await pauseCompleter!.future;
    }
  }

  @override
  Future<void> resumeWakeWord() async {
    resumeWakeWordCalls++;
    events.add('bridge.resumeWakeWord');
  }

  @override
  Future<bool> isOverlayPermissionGranted() async => true;

  @override
  Future<void> requestOverlayPermission() async {}

  @override
  Future<bool> isWakeWordModelReady() async => true;

  @override
  Future<bool> downloadWakeWordModel({
    void Function(int progress)? onProgress,
  }) async => true;

  @override
  Future<bool> ensureHandsFreeReady(BuildContext context) async => true;

  @override
  Future<void> runFirstLaunchHandsFreeSetup(BuildContext context) async {}

  @override
  Future<bool> isMicrophonePermissionGranted() async => true;

  @override
  Future<bool> requestVoicePermissions() async => true;

  @override
  Future<bool> hasPromptedHandsFree() async => true;

  @override
  Future<void> setHandsFreePrompted(bool prompted) async {}

  @override
  Future<Map<String, dynamic>> openApp(String appName) async => {
    'success': true,
    'message': 'Opening $appName.',
  };

  @override
  Future<Map<String, dynamic>> callContact(String target) async => {
    'success': true,
    'message': 'Calling $target.',
  };
}

class _FakeSpeechService implements ISpeechRecognitionService {
  final List<String> events;
  _FakeSpeechService(this.events);

  @override
  VoidCallback? onListeningStopped;

  @override
  Function(String error)? onError;

  bool _isListening = false;
  Function(String text, bool isFinal)? _onResult;
  bool throwOnStart = false;

  @override
  bool get isListening => _isListening;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get soundLevelStream => const Stream.empty();

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> requestMicrophonePermission() async => true;

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Function(double soundLevel)? onSoundLevel,
    Duration? pauseFor,
    Duration? listenFor,
  }) async {
    if (throwOnStart) {
      throw Exception('Microphone permission required');
    }
    events.add('speech.startListening');
    _isListening = true;
    _onResult = onResult;
  }

  @override
  Future<void> stopListening() async {
    events.add('speech.stopListening');
    _isListening = false;
  }

  @override
  Future<void> cancelListening() async {
    events.add('speech.cancelListening');
    _isListening = false;
  }

  void emitResult(String text, {required bool isFinal}) {
    _onResult?.call(text, isFinal);
  }

  void emitError(String error) {
    _isListening = false;
    onError?.call(error);
    onListeningStopped?.call();
  }

  void emitStopped() {
    _isListening = false;
    onListeningStopped?.call();
  }
}

class _FakeTtsService implements ITextToSpeechService {
  final List<String> events;
  _FakeTtsService(this.events);

  @override
  VoidCallback? onCompletion;

  @override
  VoidCallback? onCancel;

  @override
  Function(String error)? onError;

  bool _isSpeaking = false;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Stream<bool> get speakingStateStream => const Stream.empty();

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> speak(String text) async {
    events.add('tts.speak');
    _isSpeaking = true;
  }

  @override
  Future<void> stop() async {
    if (_isSpeaking) {
      events.add('tts.stop');
      _isSpeaking = false;
      onCancel?.call();
    }
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> setLanguage(String lang) async {}

  void completeSpeaking() {
    _isSpeaking = false;
    onCompletion?.call();
  }

  void failSpeaking(String err) {
    _isSpeaking = false;
    onError?.call(err);
  }
}

ProviderContainer _createContainer({
  required _FakeNativeVoiceBridge bridge,
  required _FakeSpeechService speech,
  required _FakeTtsService tts,
}) {
  final engine = KeeConversationEngine(
    memoryRepo: _FakeMemoryRepository(),
    reminderRepo: _FakeReminderRepository(),
    notificationService: NotificationService.instance,
    recallEngine: RecallEngine(),
  );

  return ProviderContainer(
    overrides: [
      nativeVoiceBridgeProvider.overrideWithValue(bridge),
      speechRecognitionServiceProvider.overrideWithValue(speech),
      ttsServiceProvider.overrideWithValue(tts),
      conversationEngineProvider.overrideWithValue(engine),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Hands-Free Voice Lifecycle & Microphone Coordination Tests', () {
    group('VoiceAssistantController', () {
      setUp(() {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
      });

      tearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      test(
        'duplicate startup prevention: controller init does not call startBackgroundListening',
        () async {
          final bridge = _FakeNativeVoiceBridge()..persistedHandsFree = true;
          final speech = _FakeSpeechService(bridge.events);
          final tts = _FakeTtsService(bridge.events);
          final container = _createContainer(
            bridge: bridge,
            speech: speech,
            tts: tts,
          );
          addTearDown(container.dispose);

          container.read(voiceAssistantProvider);
          await Future<void>.delayed(Duration.zero);

          expect(bridge.startBackgroundCalls, equals(0));
          expect(
            container.read(voiceAssistantProvider).isHandsFreeEnabled,
            isTrue,
          );
        },
      );

      test(
        'explicit opt-out is preserved and prevents wake-word handover calls',
        () async {
          final bridge = _FakeNativeVoiceBridge()..persistedHandsFree = false;
          final speech = _FakeSpeechService(bridge.events);
          final tts = _FakeTtsService(bridge.events);
          final container = _createContainer(
            bridge: bridge,
            speech: speech,
            tts: tts,
          );
          addTearDown(container.dispose);

          final ctrl = container.read(voiceAssistantProvider.notifier);
          await Future<void>.delayed(Duration.zero);

          expect(
            container.read(voiceAssistantProvider).isHandsFreeEnabled,
            isFalse,
          );

          await ctrl.startListening();
          speech.emitStopped();
          await Future<void>.delayed(Duration.zero);

          expect(bridge.pauseWakeWordCalls, equals(0));
          expect(bridge.resumeWakeWordCalls, equals(0));
        },
      );

      test(
        'microphone handover order waits for pauseWakeWord before listening and resumes only after TTS completion',
        () async {
          final bridge = _FakeNativeVoiceBridge();
          final speech = _FakeSpeechService(bridge.events);
          final tts = _FakeTtsService(bridge.events);
          final container = _createContainer(
            bridge: bridge,
            speech: speech,
            tts: tts,
          );
          addTearDown(container.dispose);

          final ctrl = container.read(voiceAssistantProvider.notifier);
          await Future<void>.delayed(Duration.zero);

          bridge.pauseCompleter = Completer<void>();
          final listenFuture = ctrl.startListening();
          await Future<void>.delayed(Duration.zero);

          // Must pause Vosk first and NOT open Flutter mic until pause completes
          expect(bridge.events, equals(['bridge.pauseWakeWord']));

          bridge.pauseCompleter!.complete();
          await listenFuture;

          expect(
            bridge.events,
            equals(['bridge.pauseWakeWord', 'speech.startListening']),
          );

          speech.emitResult('hello kee', isFinal: true);
          await Future<void>.delayed(const Duration(milliseconds: 20));

          // During processing and TTS speaking, Vosk must NOT be resumed yet
          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.speaking),
          );
          expect(bridge.resumeWakeWordCalls, equals(0));

          tts.completeSpeaking();
          await Future<void>.delayed(Duration.zero);

          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.idle),
          );
          expect(bridge.resumeWakeWordCalls, equals(1));
          expect(bridge.events.last, equals('bridge.resumeWakeWord'));
        },
      );

      test(
        'no-speech and aborted callbacks dismiss session and resume Vosk',
        () async {
          final bridge = _FakeNativeVoiceBridge();
          final speech = _FakeSpeechService(bridge.events);
          final tts = _FakeTtsService(bridge.events);
          final container = _createContainer(
            bridge: bridge,
            speech: speech,
            tts: tts,
          );
          addTearDown(container.dispose);

          final ctrl = container.read(voiceAssistantProvider.notifier);
          await Future<void>.delayed(Duration.zero);

          await ctrl.startListening();
          speech.emitError('no-speech');
          await Future<void>.delayed(Duration.zero);

          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.idle),
          );
          expect(bridge.resumeWakeWordCalls, equals(1));

          await ctrl.startListening();
          speech.emitError('aborted');
          await Future<void>.delayed(Duration.zero);

          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.idle),
          );
          expect(bridge.resumeWakeWordCalls, equals(2));
        },
      );

      test('recognition ending without a final result resumes Vosk', () async {
        final bridge = _FakeNativeVoiceBridge();
        final speech = _FakeSpeechService(bridge.events);
        final tts = _FakeTtsService(bridge.events);
        final container = _createContainer(
          bridge: bridge,
          speech: speech,
          tts: tts,
        );
        addTearDown(container.dispose);

        final ctrl = container.read(voiceAssistantProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        await ctrl.startListening();
        speech.emitResult('partial words', isFinal: false);
        speech.emitStopped();
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(voiceAssistantProvider).state,
          equals(AssistantState.idle),
        );
        expect(bridge.resumeWakeWordCalls, equals(1));
      });

      test(
        'TTS interruption keeps Vosk paused during the new turn and resumes only when done',
        () async {
          final bridge = _FakeNativeVoiceBridge();
          final speech = _FakeSpeechService(bridge.events);
          final tts = _FakeTtsService(bridge.events);
          final container = _createContainer(
            bridge: bridge,
            speech: speech,
            tts: tts,
          );
          addTearDown(container.dispose);

          final ctrl = container.read(voiceAssistantProvider.notifier);
          await Future<void>.delayed(Duration.zero);

          await ctrl.startListening();
          speech.emitResult('hi kee', isFinal: true);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.speaking),
          );

          await ctrl.interrupt();
          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.listening),
          );
          expect(bridge.resumeWakeWordCalls, equals(0));
          expect(bridge.pauseWakeWordCalls, equals(2));

          tts.completeSpeaking(); // stale completion should be ignored
          await Future<void>.delayed(Duration.zero);
          expect(bridge.resumeWakeWordCalls, equals(0));

          await ctrl.dismissSession();
          expect(bridge.resumeWakeWordCalls, equals(1));
        },
      );

      test(
        'error recovery stops mic/TTS, resumes Vosk, and returns to idle after 4s',
        () async {
          final bridge = _FakeNativeVoiceBridge();
          final speech = _FakeSpeechService(bridge.events)..throwOnStart = true;
          final tts = _FakeTtsService(bridge.events);
          final container = _createContainer(
            bridge: bridge,
            speech: speech,
            tts: tts,
          );
          addTearDown(container.dispose);

          final ctrl = container.read(voiceAssistantProvider.notifier);
          await Future<void>.delayed(Duration.zero);

          await ctrl.startListening();
          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.error),
          );
          expect(bridge.resumeWakeWordCalls, equals(1));

          await Future<void>.delayed(
            const Duration(seconds: 4, milliseconds: 50),
          );
          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.idle),
          );
        },
      );

      test(
        'continuous mode keeps Vosk paused for follow-up turn and resumes after 7s timeout',
        () async {
          final bridge = _FakeNativeVoiceBridge();
          final speech = _FakeSpeechService(bridge.events);
          final tts = _FakeTtsService(bridge.events);
          final container = _createContainer(
            bridge: bridge,
            speech: speech,
            tts: tts,
          );
          addTearDown(container.dispose);

          final ctrl = container.read(voiceAssistantProvider.notifier);
          await Future<void>.delayed(Duration.zero);
          ctrl.setContinuousMode(true);

          await ctrl.startListening();
          speech.emitResult('hello', isFinal: true);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.speaking),
          );

          tts.completeSpeaking();
          await Future<void>.delayed(Duration.zero);

          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.listening),
          );
          expect(bridge.resumeWakeWordCalls, equals(0));

          await Future<void>.delayed(
            const Duration(seconds: 7, milliseconds: 100),
          );
          expect(
            container.read(voiceAssistantProvider).state,
            equals(AssistantState.idle),
          );
          expect(bridge.resumeWakeWordCalls, equals(1));
        },
      );
    });

    testWidgets(
      'VoiceCaptureDialog pauses wake word on open and resumes on close',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        final bridge = _FakeNativeVoiceBridge();
        final speech = _FakeSpeechService(bridge.events);
        final tts = _FakeTtsService(bridge.events);

        // Mock speech_to_text plugin channel so VoiceCaptureDialog initializes cleanly
        const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(sttChannel, (call) async {
              if (call.method == 'initialize') return true;
              if (call.method == 'listen') return true;
              if (call.method == 'stop') return true;
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(sttChannel, null);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              nativeVoiceBridgeProvider.overrideWithValue(bridge),
              speechRecognitionServiceProvider.overrideWithValue(speech),
              ttsServiceProvider.overrideWithValue(tts),
            ],
            child: const MaterialApp(
              home: Scaffold(body: VoiceCaptureDialog()),
            ),
          ),
        );

        await tester.pump();
        expect(bridge.pauseWakeWordCalls, equals(1));

        // Dispose dialog and advance past speech_to_text's 2s internal stop timer
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));

        expect(bridge.resumeWakeWordCalls, equals(1));
      },
    );
  });
}
