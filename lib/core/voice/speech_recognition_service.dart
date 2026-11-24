import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

abstract class ISpeechRecognitionService {
  Future<bool> initialize();
  Future<bool> requestMicrophonePermission();
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Function(double soundLevel)? onSoundLevel,
    Duration? pauseFor,
    Duration? listenFor,
  });
  Future<void> stopListening();
  Future<void> cancelListening();
  bool get isListening;
  bool get isAvailable;
  Stream<double> get soundLevelStream;
}

class SpeechToTextService implements ISpeechRecognitionService {
  static final SpeechToTextService _instance = SpeechToTextService._internal();
  factory SpeechToTextService() => _instance;
  SpeechToTextService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  bool _hasPermission = false;

  final StreamController<double> _soundLevelController = StreamController<double>.broadcast();

  VoidCallback? onListeningStarted;
  VoidCallback? onListeningStopped;
  Function(String error)? onError;

  @override
  bool get isListening => _isListening;

  @override
  bool get isAvailable => _speech.isAvailable;

  @override
  Stream<double> get soundLevelStream => _soundLevelController.stream;

  @override
  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      _hasPermission = status.isGranted;
      return _hasPermission;
    } catch (e) {
      debugPrint('[SpeechToTextService] Permission request failed: $e');
      return false;
    }
  }

  @override
  Future<bool> initialize() async {
    if (_isInitialized && _speech.isAvailable) return true;

    try {
      _hasPermission = await Permission.microphone.isGranted;
      if (!_hasPermission) {
        _hasPermission = await requestMicrophonePermission();
      }

      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'listening') {
            _isListening = true;
            onListeningStarted?.call();
          } else if (status == 'notListening' || status == 'done') {
            _isListening = false;
            onListeningStopped?.call();
          }
        },
        onError: (SpeechRecognitionError error) {
          _isListening = false;
          onListeningStopped?.call();
          onError?.call(error.errorMsg);
          debugPrint('[SpeechToTextService] Error: ${error.errorMsg} (permanent: ${error.permanent})');
        },
        debugLogging: kDebugMode,
      );

      _isInitialized = available;
      return available;
    } catch (e) {
      debugPrint('[SpeechToTextService] Initialize error: $e');
      _isInitialized = false;
      return false;
    }
  }

  @override
  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    Function(double soundLevel)? onSoundLevel,
    Duration? pauseFor,
    Duration? listenFor,
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        throw Exception('Speech recognition could not be initialized. Please verify microphone permission.');
      }
    }

    if (_speech.isListening) {
      await stopListening();
    }

    try {
      _isListening = true;
      final options = stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: false,
        partialResults: true,
        pauseFor: pauseFor ?? const Duration(seconds: 3),
        listenFor: listenFor ?? const Duration(seconds: 30),
        localeId: 'en_US',
      );

      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        listenOptions: options,
        onSoundLevelChange: (level) {
          // Normalize level (speech_to_text sound level is typically -2 to 10 or 0 to 10)
          final normalized = ((level + 2) / 12.0).clamp(0.0, 1.0);
          _soundLevelController.add(normalized);
          onSoundLevel?.call(normalized);
        },
      );
    } catch (e) {
      _isListening = false;
      debugPrint('[SpeechToTextService] Listen error: $e');
      rethrow;
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
      _isListening = false;
    } catch (e) {
      debugPrint('[SpeechToTextService] Stop error: $e');
    }
  }

  @override
  Future<void> cancelListening() async {
    try {
      if (_speech.isListening) {
        await _speech.cancel();
      }
      _isListening = false;
    } catch (e) {
      debugPrint('[SpeechToTextService] Cancel error: $e');
    }
  }

  void dispose() {
    _soundLevelController.close();
  }
}
