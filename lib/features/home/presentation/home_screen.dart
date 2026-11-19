import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/kee_logo.dart';
import '../../capture/presentation/quick_capture_sheet.dart';
import '../../capture/presentation/voice_capture_dialog.dart';
import '../../memories/data/memory_model.dart';
import '../../memories/data/memory_repository.dart';
import '../../reminders/data/reminder_model.dart';
import '../../reminders/data/reminder_repository.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memoriesAsync = ref.watch(memoriesStreamProvider);
    final remindersAsync = ref.watch(remindersStreamProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(memoriesStreamProvider);
            ref.invalidate(remindersStreamProvider);
            ref.invalidate(tasksStreamProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Friendly Greeting Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const KeeLogo(size: 44),
                        const SizedBox(width: AppSpacing.sm),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('EEEE, MMMM d').format(DateTime.now()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.mic_rounded),
                      tooltip: 'Voice capture',
                      onPressed: () => VoiceCaptureDialog.show(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // 2. Prominent Quick Capture Bar
                GestureDetector(
                  onTap: () => QuickCaptureSheet.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: theme.colorScheme.outline),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Tell Kee anything. It remembers...',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Text(
                            'CAPTURE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 3. Quick "Ask Kee" recall banner
                InkWell(
                  onTap: () => context.go('/ask-kee'),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary.withOpacity(0.08),
                          theme.colorScheme.secondary.withOpacity(0.04),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                          child: Icon(
                            Icons.psychology_alt_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ask Kee anything',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Instant recall across all your memories & tasks',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 4. Upcoming Reminders Section
                _buildSectionHeader(
                  context,
                  title: 'Upcoming Reminders',
                  onSeeAll: () => context.go('/reminders'),
                ),
                const SizedBox(height: AppSpacing.xs),
                remindersAsync.when(
                  data: (reminders) {
                    final upcoming = reminders
                        .where((r) => r.isEnabled && r.scheduledAt.isAfter(DateTime.now()))
                        .take(3)
                        .toList();

                    if (upcoming.isEmpty) {
                      return _buildEmptyCard(
                        context,
                        icon: Icons.notifications_none_rounded,
                        message: 'No upcoming reminders. You are all caught up!',
                      );
                    }

                    return Column(
                      children: upcoming.map((r) => _buildReminderItem(context, ref, r)).toList(),
                    );
                  },
                  loading: () => const Center(child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  )),
                  error: (e, _) => Text('Error loading reminders: $e'),
                ),
                const SizedBox(height: AppSpacing.xl),

                // 5. Recent Memories Section
                _buildSectionHeader(
                  context,
                  title: 'Recent Memories',
                  onSeeAll: () => context.go('/memories'),
                ),
                const SizedBox(height: AppSpacing.xs),
                memoriesAsync.when(
                  data: (memories) {
                    final recent = memories.take(4).toList();

                    if (recent.isEmpty) {
                      return _buildEmptyCard(
                        context,
                        icon: Icons.note_alt_outlined,
                        message: 'No memories saved yet. Try saving a note or thought above.',
                      );
                    }

                    return Column(
                      children: recent.map((m) => _buildMemoryItem(context, m)).toList(),
                    );
                  },
                  loading: () => const Center(child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  )),
                  error: (e, _) => Text('Error loading memories: $e'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required VoidCallback onSeeAll,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        TextButton(
          onPressed: onSeeAll,
          child: const Text('See all', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildReminderItem(BuildContext context, WidgetRef ref, ReminderModel reminder) {
    final theme = Theme.of(context);
    final timeStr = DateFormat('EEE, MMM d • h:mm a').format(reminder.scheduledAt);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
          child: Icon(Icons.alarm_rounded, color: theme.colorScheme.primary, size: 20),
        ),
        title: Text(
          reminder.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          timeStr,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.snooze_rounded, size: 20),
          tooltip: 'Snooze 1 hour',
          onPressed: () async {
            await ref.read(reminderRepositoryProvider).snoozeReminder(
              reminder.id,
              const Duration(hours: 1),
            );
            ref.invalidate(remindersStreamProvider);
          },
        ),
      ),
    );
  }

  Widget _buildMemoryItem(BuildContext context, MemoryModel memory) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: () => context.go('/memories/detail/${memory.id}'),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      memory.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    DateFormat('MMM d').format(memory.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                memory.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                memory.originalContent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
