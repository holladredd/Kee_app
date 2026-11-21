import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/kee_logo.dart';
import '../../../core/widgets/kee_onboarding_sheet.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/intelligence/local_ai_runner.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/database/database_helper.dart';
import '../../memories/data/memory_repository.dart';
import '../../reminders/data/reminder_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final aiEngine = ref.watch(aiEngineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        children: [
          // Section: Appearance
          _buildSectionTitle(theme, 'Appearance'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Theme Mode'),
                  subtitle: Text(
                    themeMode == ThemeMode.system
                        ? 'Follow System'
                        : themeMode == ThemeMode.dark
                            ? 'Dark Mode'
                            : 'Light Mode',
                  ),
                  trailing: DropdownButton<ThemeMode>(
                    value: themeMode,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(themeModeProvider.notifier).setThemeMode(val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Section: Notifications & Alarms
          _buildSectionTitle(theme, 'Notifications & Reminders'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Device Notification Permissions'),
                  subtitle: const Text('Required to deliver background reminder notifications'),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      final granted = await NotificationService.instance.requestPermissions();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(granted ? 'Notifications are active and permitted' : 'Notification check completed'),
                          ),
                        );
                      }
                    },
                    child: const Text('Check'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notification_important_outlined),
                  title: const Text('Send Test Reminder'),
                  subtitle: const Text('Test device alarm notification delivery (triggers in 5s)'),
                  trailing: const Icon(Icons.send_rounded, size: 20),
                  onTap: () async {
                    final granted = await NotificationService.instance.requestPermissions();
                    if (!granted) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enable notification permissions first.')),
                        );
                      }
                      return;
                    }
                    final testDate = DateTime.now().add(const Duration(seconds: 5));
                    await NotificationService.instance.scheduleReminder(
                      notificationId: 99999,
                      title: 'Kee Test Reminder',
                      body: 'Your device notification channel is functioning properly.',
                      scheduledDate: testDate,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Test notification scheduled for 5 seconds from now.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.volume_up_outlined),
                  title: Text('Sound & Vibration'),
                  subtitle: Text('High-priority alert channel with vibration enabled'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Section: Personal Data & Privacy Control Area
          _buildSectionTitle(theme, 'Personal Data & Memory Vault'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('Review Saved Memories'),
                  subtitle: const Text('Inspect, search, or delete stored personal memories'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/memories'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.alarm_outlined),
                  title: const Text('Manage Scheduled Reminders'),
                  subtitle: const Text('View active alarms, toggle or remove reminders'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/reminders'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Export Local Data (JSON)'),
                  subtitle: const Text('Back up all memories, tasks, and reminders to a file'),
                  onTap: () async {
                    final memories = await ref.read(memoryRepositoryProvider).getAllMemories();
                    final tasks = await ref.read(reminderRepositoryProvider).getTasks();
                    final reminders = await ref.read(reminderRepositoryProvider).getReminders();

                    final exportData = {
                      'app': 'Kee',
                      'version': '1.0.0',
                      'exported_at': DateTime.now().toIso8601String(),
                      'memories': memories.map((m) => m.toMap()).toList(),
                      'tasks': tasks.map((t) => t.toMap()).toList(),
                      'reminders': reminders.map((r) => r.toMap()).toList(),
                    };

                    final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);
                    await SharePlus.instance.share(
                      ShareParams(
                        text: jsonStr,
                        subject: 'Kee Backup Data',
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                  title: Text(
                    'Clear All Local Memory Data',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text('Wipes local memories, tasks, and reminders'),
                  onTap: () => _showClearDataConfirmation(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Privacy & Offline Guarantee'),
                  subtitle: const Text('Your memories stay on your device. Zero external data tracking.'),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Kee Privacy Principles'),
                        content: const Text(
                          '1. User data belongs solely to the user.\n'
                          '2. Reminders work offline without internet.\n'
                          '3. No subscriptions, credits, or paid tiers.\n'
                          '4. Memories are never sent to external AI services without your explicit consent.\n'
                          '5. All classification and recall runs locally.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Section: Intelligence & AI
          _buildSectionTitle(theme, 'Intelligence Engine'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.psychology_rounded),
                  title: const Text('Current Processing Engine'),
                  subtitle: Text(aiEngine.name),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: const Text(
                      'OFFLINE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.bolt_rounded),
                  title: Text('Deterministic Intent Classifier'),
                  subtitle: Text('Fast, zero-latency rule classification & natural-language date parsing'),
                  trailing: Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Section: Account
          _buildSectionTitle(theme, 'Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Signed in as'),
                  subtitle: Text(
                    ref.watch(currentUserProvider)?.email ?? 'Local Offline Mode',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Sign Out',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: const Text('Clear active session on this device'),
                  onTap: () => _showLogoutConfirmation(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Section: About
          _buildSectionTitle(theme, 'About'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: KeeLogo(size: 42),
                  title: Text(
                    'Kee',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'K.E.E. · Knowledge Extension Entity\nYour memory. Extended.',
                  ),
                  isThreeLine: true,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Brand Philosophy & Introduction'),
                  subtitle: const Text('Review what Kee is and how it extends your memory'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () => KeeOnboardingSheet.show(context, isReview: true),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.verified_outlined),
                  title: Text('Version 1.0.0'),
                  subtitle: Text('Local-First Personal Technology'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  void _showClearDataConfirmation(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Local Data?'),
        content: const Text(
          'This will permanently delete all memories, tasks, and reminders stored on this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseHelper.instance.clearAll();
              ref.invalidate(memoriesStreamProvider);
              ref.invalidate(remindersStreamProvider);
              ref.invalidate(tasksStreamProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All local memory data has been cleared.')),
                );
              }
            },
            child: Text(
              'Delete Everything',
              style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark
        ? const Color(0xFFE8D0B2)
        : const Color(0xFFA6855B);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        icon: Icon(
          Icons.logout_rounded,
          color: accentColor,
          size: 40,
        ),
        title: Text(
          'Sign Out?',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Your local data will be preserved. You can sign back in anytime.',
          style: TextStyle(
            color: isDark
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: Text(
              'Sign Out',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
