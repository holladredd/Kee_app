import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:kee/core/constants/app_spacing.dart';
import 'quick_capture_sheet.dart';

class VoiceCaptureDialog extends StatefulWidget {
  const VoiceCaptureDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const VoiceCaptureDialog(),
    );
  }

  @override
  State<VoiceCaptureDialog> createState() => _VoiceCaptureDialogState();
}

class _VoiceCaptureDialogState extends State<VoiceCaptureDialog> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _wordsSpoken = '';
  String _statusText = 'Initializing voice engine...';
  bool _hasSpeechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) {
            setState(() {
              if (status == 'listening') {
                _statusText = 'Listening... Speak naturally';
                _isListening = true;
              } else if (status == 'notListening') {
                _statusText = 'Tap mic to resume speaking';
                _isListening = false;
              }
            });
          }
        },
        onError: (errorNotification) {
          if (mounted) {
            setState(() {
              _statusText = 'Voice input: ${errorNotification.errorMsg}';
              _isListening = false;
            });
          }
        },
      );

      setState(() {
        _hasSpeechAvailable = available;
        if (available) {
          _statusText = 'Ready. Listening...';
          _startListening();
        } else {
          _statusText = 'Speech recognition not available on this device';
        }
      });
    } catch (e) {
      setState(() {
        _statusText = 'Voice recognition error: $e';
        _hasSpeechAvailable = false;
      });
    }
  }

  void _startListening() async {
    if (!_hasSpeechAvailable) return;
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _wordsSpoken = result.recognizedWords;
          });
        }
      },
    );
    setState(() => _isListening = true);
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _confirmAndProceed() {
    _stopListening();
    Navigator.pop(context);
    QuickCaptureSheet.show(context, initialText: _wordsSpoken);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      title: Row(
        children: [
          Icon(Icons.mic_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          const Text('Voice Capture'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _statusText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Speech display area
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            constraints: const BoxConstraints(minHeight: 100, maxHeight: 200),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: _isListening
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: _isListening ? 1.5 : 1,
              ),
            ),
            child: SingleChildScrollView(
              child: Text(
                _wordsSpoken.isEmpty
                    ? (_isListening ? 'Speak your thoughts or reminders...' : 'No words captured yet.')
                    : _wordsSpoken,
                style: TextStyle(
                  fontSize: 16,
                  color: _wordsSpoken.isEmpty
                      ? theme.colorScheme.onSurfaceVariant.withOpacity(0.6)
                      : theme.colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Mic toggle button
          Center(
            child: FloatingActionButton(
              onPressed: _hasSpeechAvailable
                  ? (_isListening ? _stopListening : _startListening)
                  : null,
              backgroundColor: _isListening
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              foregroundColor: Colors.white,
              child: Icon(_isListening ? Icons.mic_off_rounded : Icons.mic_rounded),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _wordsSpoken.trim().isNotEmpty ? _confirmAndProceed : null,
          child: const Text('Review & Save'),
        ),
      ],
    );
  }
}
