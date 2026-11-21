import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/memories/data/memory_repository.dart';
import '../../features/reminders/data/reminder_repository.dart';
import '../notifications/notification_service.dart';
import 'kee_conversation_engine.dart';
import 'recall_engine.dart';

final conversationEngineProvider = Provider<KeeConversationEngine>((ref) {
  final memoryRepo = ref.watch(memoryRepositoryProvider);
  final reminderRepo = ref.watch(reminderRepositoryProvider);

  return KeeConversationEngine(
    memoryRepo: memoryRepo,
    reminderRepo: reminderRepo,
    notificationService: NotificationService.instance,
    recallEngine: RecallEngine(),
  );
});
