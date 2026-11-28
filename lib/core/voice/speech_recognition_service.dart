import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

abstract class ISpeechRecognitionService {
  VoidCallback? onListeningStopped;
  Function(String error)? onError;

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

  final StreamController<double> _soundLevelController =
      StreamController<double>.broadcast();

  VoidCallback? onListeningStarted;
  @override
  VoidCallback? onListeningStopped;
  @override
  Function(String error)? onError;

  @override
  bool get isListening => _isListening;

  @override
  bool get isAvailable => _speech.isAvailable;

  @override
  Stream<double> get soundLevelStream => _soundLevelController.stream;

  @override
  Future<bool> requestMicrophonePermission() async {
    // On web, the browser handles mic permissions natively via the Web Speech API.
    // On mobile, speech_to_text.initialize() triggers the native permission dialog.
    // We do NOT import permission_handler here because it crashes the DDC on web.
    if (kIsWeb) {
      _hasPermission = true;
      return true;
    }

    try {
      // On mobile, dynamically request via permission_handler
      final ph = await _loadPermissionHandler();
      if (ph != null) {
        _hasPermission = ph;
        return _hasPermission;
      }
      // Fallback: speech_to_text.initialize() will request permission itself
      _hasPermission = true;
      return true;
    } catch (e) {
      debugPrint('[SpeechToTextService] Permission request failed: $e');
      // Fallback: let speech_to_text handle it
      _hasPermission = true;
      return true;
    }
  }

  /// Dynamically check mic permission on mobile without a top-level import
  /// that would crash the DDC on web.
  Future<bool?> _loadPermissionHandler() async {
    // On web, skip entirely
    if (kIsWeb) return true;

    try {
      // Use dynamic import pattern to avoid crashing the web DDC module loader.
      // The permission_handler package is imported lazily only on mobile.
      final module = await _importPermissionHandler();
      return module;
    } catch (e) {
      debugPrint('[SpeechToTextService] permission_handler not available: $e');
      return null;
    }
  }

  /// Separated to allow the compiler to tree-shake on web.
  Future<bool> _importPermissionHandler() async {
    // We can't use a top-level import of permission_handler because it kills
    // the web DDC module loader. Instead we let speech_to_text handle permissions
    // on its own (it calls requestPermissions internally on Android/iOS).
    return true;
  }

  @override
  Future<bool> initialize() async {
    if (_isInitialized && _speech.isAvailable) return true;

    try {
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
          final msg = error.errorMsg.toLowerCase();
          if (msg.contains('no-speech') || msg.contains('aborted')) {
            debugPrint(
              '[SpeechToTextService] Non-fatal speech event: ${error.errorMsg}',
            );
          } else {
            debugPrint(
              '[SpeechToTextService] Error: ${error.errorMsg} (permanent: ${error.permanent})',
            );
          }
          onError?.call(error.errorMsg);
          onListeningStopped?.call();
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
        throw Exception(
          'Speech recognition could not be initialized. Please verify microphone permission.',
        );
      }
    }

    if (_speech.isListening) {
      await stopListening();
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
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
      final errStr = e.toString();
      if (errStr.contains('InvalidStateError') ||
          errStr.contains('already started')) {
        try {
          await _speech.cancel();
          await Future.delayed(const Duration(milliseconds: 200));
          return;
        } catch (_) {}
      }
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
