import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/memories/data/memory_repository.dart';
import '../../features/reminders/data/reminder_repository.dart';
import '../notifications/notification_service.dart';
import '../voice/native_voice_bridge.dart';
import 'kee_conversation_engine.dart';
import 'recall_engine.dart';

final conversationEngineProvider = Provider<KeeConversationEngine>((ref) {
  final memoryRepo = ref.watch(memoryRepositoryProvider);
  final reminderRepo = ref.watch(reminderRepositoryProvider);
  final voiceBridge = ref.read(nativeVoiceBridgeProvider);

  return KeeConversationEngine(
    memoryRepo: memoryRepo,
    reminderRepo: reminderRepo,
    notificationService: NotificationService.instance,
    recallEngine: RecallEngine(),
    deviceActionHandler: (action, target) {
      if (action == 'openApp') {
        return voiceBridge.openApp(target);
      }
      if (action == 'callContact') {
        return voiceBridge.callContact(target);
      }
      return Future.value({'success': false, 'message': 'Unsupported action.'});
    },
  );
});
