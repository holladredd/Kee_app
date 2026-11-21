import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_spacing.dart';
import '../../capture/presentation/quick_capture_sheet.dart';
import '../data/reminder_model.dart';
import '../data/task_model.dart';
import '../data/reminder_repository.dart';

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remindersAsync = ref.watch(remindersStreamProvider);
    final tasksAsync = ref.watch(tasksStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders & Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add reminder',
            onPressed: () => QuickCaptureSheet.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(text: 'Reminders'),
            Tab(text: 'Tasks'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Reminders (Upcoming, Overdue, Recurring)
          remindersAsync.when(
            data: (reminders) {
              final now = DateTime.now();
              final upcoming = reminders.where((r) => r.scheduledAt.isAfter(now)).toList();
              final overdue = reminders.where((r) => r.scheduledAt.isBefore(now) && r.isEnabled).toList();

              if (reminders.isEmpty) {
                return _buildEmptyState(
                  context,
                  icon: Icons.alarm_off_rounded,
                  title: 'No reminders set',
                  subtitle: 'Capture what matters naturally to let Kee manage reminders and extend your memory.',
                );
              }

              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (overdue.isNotEmpty) ...[
                    _buildSubheading(theme, 'Overdue', color: theme.colorScheme.error),
                    ...overdue.map((r) => _buildReminderTile(context, r, isOverdue: true)),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (upcoming.isNotEmpty) ...[
                    _buildSubheading(theme, 'Upcoming'),
                    ...upcoming.map((r) => _buildReminderTile(context, r)),
                  ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading reminders: $e')),
          ),

          // Tab 2: Pending Tasks
          tasksAsync.when(
            data: (tasks) {
              final pendingTasks = tasks.where((t) => !t.isCompleted).toList();
              if (pendingTasks.isEmpty) {
                return _buildEmptyState(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  title: 'All tasks completed!',
                  subtitle: 'Capture tasks with Kee to keep commitments clear and your memory extended.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: pendingTasks.length,
                itemBuilder: (context, index) {
                  final task = pendingTasks[index];
                  return _buildTaskTile(context, task);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading tasks: $e')),
          ),

          // Tab 3: Completed Tasks
          tasksAsync.when(
            data: (tasks) {
              final completedTasks = tasks.where((t) => t.isCompleted).toList();
              if (completedTasks.isEmpty) {
                return _buildEmptyState(
                  context,
                  icon: Icons.done_all_rounded,
                  title: 'No completed tasks yet',
                  subtitle: 'Tasks you complete will appear here for reference.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: completedTasks.length,
                itemBuilder: (context, index) {
                  final task = completedTasks[index];
                  return _buildTaskTile(context, task);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading tasks: $e')),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => QuickCaptureSheet.show(context),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildSubheading(ThemeData theme, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildReminderTile(BuildContext context, ReminderModel reminder, {bool isOverdue = false}) {
    final theme = Theme.of(context);
    final repo = ref.read(reminderRepositoryProvider);
    final timeStr = DateFormat('EEE, MMM d • h:mm a').format(reminder.scheduledAt);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(
          Icons.alarm_rounded,
          color: isOverdue ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        title: Text(
          reminder.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            decoration: !reminder.isEnabled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 12,
                color: isOverdue ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (reminder.isRecurring)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Repeats ${reminder.recurrenceRule}',
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (val) async {
                if (val == 'snooze_10m') {
                  await repo.snoozeReminder(reminder.id, const Duration(minutes: 10));
                } else if (val == 'snooze_1h') {
                  await repo.snoozeReminder(reminder.id, const Duration(hours: 1));
                } else if (val == 'snooze_1d') {
                  await repo.snoozeReminder(reminder.id, const Duration(days: 1));
                } else if (val == 'delete') {
                  await repo.deleteReminder(reminder.id);
                }
                ref.invalidate(remindersStreamProvider);
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'snooze_10m', child: Text('Snooze 10 mins')),
                const PopupMenuItem(value: 'snooze_1h', child: Text('Snooze 1 hour')),
                const PopupMenuItem(value: 'snooze_1d', child: Text('Snooze 1 day')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            Switch(
              value: reminder.isEnabled,
              onChanged: (val) async {
                await repo.toggleReminder(reminder.id, val);
                ref.invalidate(remindersStreamProvider);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(BuildContext context, TaskModel task) {
    final theme = Theme.of(context);
    final repo = ref.read(reminderRepositoryProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CheckboxListTile(
        value: task.isCompleted,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (val) async {
          await repo.toggleTaskCompletion(task.id, task.isCompleted);
          ref.invalidate(tasksStreamProvider);
        },
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: task.dueDate != null
            ? Text(
                'Due ${DateFormat('MMM d').format(task.dueDate!)}',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              )
            : null,
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
