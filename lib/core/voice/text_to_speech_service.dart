import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class ITextToSpeechService {
  Future<bool> initialize();
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> pause();
  Future<void> setSpeechRate(double rate);
  Future<void> setPitch(double pitch);
  Future<void> setLanguage(String lang);
  bool get isSpeaking;
  Stream<bool> get speakingStateStream;
}

class FlutterTtsService implements ITextToSpeechService {
  static final FlutterTtsService _instance = FlutterTtsService._internal();
  factory FlutterTtsService() => _instance;
  FlutterTtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  final StreamController<bool> _speakingStateController = StreamController<bool>.broadcast();

  VoidCallback? onStart;
  VoidCallback? onCompletion;
  VoidCallback? onCancel;
  Function(String error)? onError;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Stream<bool> get speakingStateStream => _speakingStateController.stream;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Audio focus & category configuration
      await _flutterTts.setSpeechRate(0.5); // 0.5 is standard conversational speed in flutter_tts
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);

      // On Android / iOS configure audio category
      if (!kIsWeb) {
        await _flutterTts.awaitSynthCompletion(true);
        await _flutterTts.awaitSpeakCompletion(true);
      }

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        _speakingStateController.add(true);
        onStart?.call();
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _speakingStateController.add(false);
        onCompletion?.call();
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        _speakingStateController.add(false);
        onCancel?.call();
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        _speakingStateController.add(false);
        onError?.call(msg.toString());
      });

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[FlutterTtsService] Initialization error: $e');
      return false;
    }
  }

  @override
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (text.trim().isEmpty) return;

    try {
      // If currently speaking, stop first to avoid overlapping speech
      if (_isSpeaking) {
        await stop();
      }
      _isSpeaking = true;
      _speakingStateController.add(true);
      await _flutterTts.speak(text);
    } catch (e) {
      _isSpeaking = false;
      _speakingStateController.add(false);
      debugPrint('[FlutterTtsService] Speak error: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
      _isSpeaking = false;
      _speakingStateController.add(false);
    } catch (e) {
      debugPrint('[FlutterTtsService] Stop error: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _flutterTts.pause();
      _isSpeaking = false;
      _speakingStateController.add(false);
    } catch (e) {
      debugPrint('[FlutterTtsService] Pause error: $e');
    }
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    // Normal rate is ~0.5 on FlutterTts
    try {
      await _flutterTts.setSpeechRate(rate.clamp(0.1, 1.0));
    } catch (e) {
      debugPrint('[FlutterTtsService] Set rate error: $e');
    }
  }

  @override
  Future<void> setPitch(double pitch) async {
    try {
      await _flutterTts.setPitch(pitch.clamp(0.5, 2.0));
    } catch (e) {
      debugPrint('[FlutterTtsService] Set pitch error: $e');
    }
  }

  @override
  Future<void> setLanguage(String lang) async {
    try {
      await _flutterTts.setLanguage(lang);
    } catch (e) {
      debugPrint('[FlutterTtsService] Set language error: $e');
    }
  }

  void dispose() {
    _speakingStateController.close();
  }
}
