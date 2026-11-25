import 'dart:io';
import 'package:flutter/foundation.dart';
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
  static const MethodChannel _channel = MethodChannel('com.kee.app/voice_service');
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
        _ref.read(unifiedChatProvider.notifier).recordVoiceTurn(
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
        if (action.savedMemory != null || action.scheduledReminder != null || action.savedTask != null) {
          _ref.read(backgroundWalkerProvider.notifier).walkNow();
        }
      } catch (e) {
        debugPrint('[NativeVoiceBridge] Error recording turn: $e');
      }

      return action.responseText;
    } catch (e) {
      debugPrint('[NativeVoiceBridge] Processing error: $e');
      return "I've saved your note: $trimmed.";
    }
  }

  Future<bool> startBackgroundListening() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final hasOverlay = await isOverlayPermissionGranted();
      if (!hasOverlay) {
        await requestOverlayPermission();
      }
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
      final res = await _channel.invokeMethod<bool>('isOverlayPermissionGranted');
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

  Future<bool> isWakeWordModelReady() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('isWakeWordModelReady');
      return res ?? false;
    } catch (e) {
      return false;
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
}
