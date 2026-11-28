import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../intelligence/conversation_provider.dart';
import '../intelligence/unified_chat_provider.dart';
import '../navigation/app_router.dart';
import '../sync/background_walker_pipeline.dart';

final nativeVoiceBridgeProvider = Provider<NativeVoiceBridge>((ref) {
  final bridge = NativeVoiceBridge(ref);
  bridge.initialize();
  return bridge;
});

class NativeVoiceBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.kee.app/voice_service',
  );
  final Ref _ref;
  void Function(int progress)? _onDownloadProgress;

  NativeVoiceBridge(this._ref);

  void initialize() {
    if (kIsWeb || !Platform.isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'processQuery') {
        final query = (call.arguments as Map?)?['query'] as String? ?? '';
        return await _handleBackgroundQuery(query);
      } else if (call.method == 'navigateTo') {
        final route = (call.arguments as Map?)?['route'] as String?;
        if (route != null && route.isNotEmpty) {
          _ref.read(appRouterProvider).go(route);
        }
        return true;
      } else if (call.method == 'modelDownloadProgress') {
        final progress = (call.arguments as Map?)?['progress'] as int? ?? 0;
        _onDownloadProgress?.call(progress);
        return true;
      }
      return null;
    });
  }

  Future<String> _handleBackgroundQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return "I'm listening.";

    try {
      final engine = _ref.read(conversationEngineProvider);
      final action = await engine.processMessage(trimmed);

      // Record in Kee's single unified chat thread
      try {
        _ref
            .read(unifiedChatProvider.notifier)
            .recordVoiceTurn(
              userText: trimmed,
              assistantText: action.responseText,
              intent: action.intent,
              savedMemory: action.savedMemory,
              scheduledReminder: action.scheduledReminder,
              savedTask: action.savedTask,
              citations: action.citedMemories,
              citedReminders: action.citedReminders,
              citedTasks: action.citedTasks,
            );

        // Run sync/consolidation walk if items saved
        if (action.savedMemory != null ||
            action.scheduledReminder != null ||
            action.savedTask != null) {
          _ref.read(backgroundWalkerProvider.notifier).walkNow();
        }
      } catch (e) {
        debugPrint('[NativeVoiceBridge] Error recording turn: $e');
      }

      return action.responseText;
    } catch (e) {
      debugPrint('[NativeVoiceBridge] Processing error: $e');
      return "I couldn't process that request. Please try again.";
    }
  }

  Future<bool> startBackgroundListening() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('startBackgroundListening');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeVoiceBridge] Start error: $e');
      return false;
    }
  }

  Future<bool> stopBackgroundListening() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('stopBackgroundListening');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeVoiceBridge] Stop error: $e');
      return false;
    }
  }

  Future<bool> isOverlayPermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>(
        'isOverlayPermissionGranted',
      );
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('[NativeVoiceBridge] Overlay permission request error: $e');
    }
  }

  Future<bool> isServiceRunning() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isServiceRunning');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> getPersistedHandsFree() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('getPersistedHandsFree');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> openApp(String appName) async {
    if (kIsWeb || !Platform.isAndroid) {
      return {
        'success': false,
        'message': 'App launching is only supported on Android.',
      };
    }
    try {
      final res = await _channel.invokeMethod<Map>('openApp', {
        'appName': appName,
      });
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      return {'success': false, 'message': "Couldn't open $appName."};
    }
  }

  Future<Map<String, dynamic>> callContact(String target) async {
    if (kIsWeb || !Platform.isAndroid) {
      return {
        'success': false,
        'message': 'Calling is only supported on Android.',
      };
    }
    try {
      final res = await _channel.invokeMethod<Map>('callContact', {
        'target': target,
      });
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      return {'success': false, 'message': "Couldn't place call to $target."};
    }
  }

  Future<Map<String, dynamic>> executeDeviceAction(
    String action,
    Map<String, dynamic> params,
  ) async {
    if (kIsWeb || !Platform.isAndroid) {
      return {
        'success': false,
        'supported': false,
        'message': 'Device actions are only supported on Android.',
      };
    }
    try {
      final res = await _channel.invokeMethod<Map>('executeDeviceAction', {
        'action': action,
        'params': params,
      });
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      return {
        'success': false,
        'message': "Couldn't execute that device action.",
      };
    }
  }

  Future<bool> isWakeWordModelReady() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('isWakeWordModelReady');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Pause native Vosk wake-word listener so Flutter speech recognition can
  /// use the microphone without conflict.
  Future<void> pauseWakeWord() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('pauseWakeWord');
    } catch (e) {
      debugPrint('[NativeVoiceBridge] pauseWakeWord error: $e');
    }
  }

  /// Resume native Vosk wake-word listener after Flutter speech recognition
  /// has released the microphone.
  Future<void> resumeWakeWord() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('resumeWakeWord');
    } catch (e) {
      debugPrint('[NativeVoiceBridge] resumeWakeWord error: $e');
    }
  }

  Future<bool> downloadWakeWordModel({
    void Function(int progress)? onProgress,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return true;
    _onDownloadProgress = onProgress;
    try {
      final res = await _channel.invokeMethod<bool>('downloadWakeWordModel');
      return res ?? false;
    } finally {
      _onDownloadProgress = null;
    }
  }

  Future<bool> isMicrophonePermissionGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>(
        'isMicrophonePermissionGranted',
      );
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestVoicePermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('requestVoicePermissions');
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeVoiceBridge] requestVoicePermissions error: $e');
      return false;
    }
  }

  Future<bool> hasPromptedHandsFree() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('hasPromptedHandsFree');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> setHandsFreePrompted(bool prompted) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setHandsFreePrompted', {
        'prompted': prompted,
      });
    } catch (e) {
      debugPrint('[NativeVoiceBridge] setHandsFreePrompted error: $e');
    }
  }

  /// Ensures microphone/notification permissions, the offline Vosk wake-word
  /// model, and overlay permission are explained/granted before enabling
  /// Hands-Free mode on Android.
  Future<bool> ensureHandsFreeReady(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final hasMic = await isMicrophonePermissionGranted();
    if (!hasMic) {
      final granted = await requestVoicePermissions();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone permission is required for hands-free wake word ("Hi Kee").',
              ),
            ),
          );
        }
        return false;
      }
    }

    final modelReady = await isWakeWordModelReady();
    if (!modelReady && context.mounted) {
      final progressNotifier = ValueNotifier<int>(0);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Setting Up Hands-Free'),
          content: ValueListenableBuilder<int>(
            valueListenable: progressNotifier,
            builder: (ctx, pct, child) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Downloading offline wake-word model (~40 MB) once so Kee listens silently without chimes...',
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: pct > 0 ? pct / 100.0 : null),
                const SizedBox(height: 8),
                Text('$pct%', style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );

      bool downloaded = false;
      String? errorMsg;
      try {
        downloaded = await downloadWakeWordModel(
          onProgress: (pct) => progressNotifier.value = pct,
        );
      } catch (e) {
        errorMsg = e.toString();
      } finally {
        progressNotifier.dispose();
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }

      if (!downloaded) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg != null
                    ? 'Could not download wake-word model: $errorMsg'
                    : 'Could not download wake-word model. Check your internet connection.',
              ),
            ),
          );
        }
        return false;
      }
    }

    final hasOverlay = await isOverlayPermissionGranted();
    if (!hasOverlay && context.mounted) {
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Floating Assistant'),
          content: const Text(
            'To summon Kee with "Hi Kee" while using other apps, Kee needs permission to display a compact floating assistant widget over other apps.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not Now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
      if (shouldRequest != true) return false;
      await requestOverlayPermission();
    }

    return true;
  }

  /// Runs once on first launch when hands-free defaults to enabled, requesting
  /// permissions and downloading the Vosk model without nagging on later launches.
  Future<void> runFirstLaunchHandsFreeSetup(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final enabled = await getPersistedHandsFree();
    if (!enabled) return;

    final prompted = await hasPromptedHandsFree();
    if (prompted) return;

    final hasMic = await isMicrophonePermissionGranted();
    final modelReady = await isWakeWordModelReady();
    final hasOverlay = await isOverlayPermissionGranted();

    if (hasMic && modelReady && hasOverlay) {
      await setHandsFreePrompted(true);
      final running = await isServiceRunning();
      if (!running) {
        await startBackgroundListening();
      }
      return;
    }

    await setHandsFreePrompted(true);
    if (!context.mounted) return;

    final ready = await ensureHandsFreeReady(context);
    if (ready) {
      await startBackgroundListening();
    }
  }
}
