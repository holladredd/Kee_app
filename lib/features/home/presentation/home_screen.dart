import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/kee_logo.dart';
import '../../../core/widgets/kee_onboarding_sheet.dart';
import '../../capture/presentation/voice_capture_dialog.dart';
import '../../memories/data/memory_repository.dart';
import '../../reminders/data/reminder_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _quickInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      KeeOnboardingSheet.checkAndShow(context);
    });
  }

  @override
  void dispose() {
    _quickInputController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final memoriesAsync = ref.watch(memoriesStreamProvider);
    final remindersAsync = ref.watch(remindersStreamProvider);

    final accentColor = isDark
        ? const Color(0xFFE8D0B2)
        : const Color(0xFFA6855B);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(memoriesStreamProvider);
            ref.invalidate(remindersStreamProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xs),

                // ─── 1. Brand & Header ────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => KeeOnboardingSheet.show(context, isReview: true),
                          child: const KeeLogo(size: 40),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Kee',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: accentColor,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '· Knowledge Extension Entity',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 0.2,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Your memory. Extended.',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ─── 2. Conversational Greeting ────────────────
                Text(
                  _getGreeting(),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Talk naturally to Kee. Tell me what to remember, schedule a reminder, or ask about anything you’ve saved.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ─── 3. Prominent Conversational Entry Point ───
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _quickInputController,
                                decoration: InputDecoration(
                                  hintText: 'Talk to Kee or ask a question...',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                                onSubmitted: (val) {
                                  if (val.trim().isNotEmpty) {
                                    context.go('/ask-kee');
                                  }
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.mic_none_rounded),
                              tooltip: 'Voice Input',
                              onPressed: () async {
                                await VoiceCaptureDialog.show(context);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_rounded),
                              tooltip: 'Open Ask Kee',
                              onPressed: () => context.go('/ask-kee'),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                      InkWell(
                        onTap: () => context.go('/ask-kee'),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppSpacing.radiusLg)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded, size: 14, color: accentColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Open full conversation with Kee',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                              Icon(Icons.chevron_right_rounded, size: 16, color: accentColor),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ─── 4. Conversational Quick Prompts ───────────
                Text(
                  'TRY SAYING TO KEE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildPromptTile(
                  context: context,
                  icon: Icons.alarm_rounded,
                  title: 'Remind me to call John tomorrow at 9 AM',
                  subtitle: 'Creates a local reminder and schedules device notification',
                  onTap: () => context.go('/ask-kee'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildPromptTile(
                  context: context,
                  icon: Icons.thumb_up_alt_outlined,
                  title: 'I prefer working early in the morning',
                  subtitle: 'Stores your personal preference for future context',
                  onTap: () => context.go('/ask-kee'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildPromptTile(
                  context: context,
                  icon: Icons.cake_outlined,
                  title: 'My mum\'s birthday is February 14',
                  subtitle: 'Remembers important dates without setting alarms',
                  onTap: () => context.go('/ask-kee'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildPromptTile(
                  context: context,
                  icon: Icons.search_rounded,
                  title: 'What do I have scheduled tomorrow?',
                  subtitle: 'Retrieves relevant memories and upcoming reminders',
                  onTap: () => context.go('/ask-kee'),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ─── 5. Ambient Memory & Reminder Status ───────
                remindersAsync.when(
                  data: (reminders) {
                    final now = DateTime.now();
                    final upcoming = reminders
                        .where((r) => r.isEnabled && r.scheduledAt.isAfter(now))
                        .toList();

                    return memoriesAsync.when(
                      data: (memories) {
                        return _buildStatusCard(
                          context,
                          memoriesCount: memories.length,
                          remindersCount: upcoming.length,
                          nextReminder: upcoming.isNotEmpty ? upcoming.first : null,
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = isDark
        ? const Color(0xFFE8D0B2)
        : const Color(0xFFA6855B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: accentColor.withValues(alpha: 0.12),
              child: Icon(icon, size: 16, color: accentColor),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"$title"',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context, {
    required int memoriesCount,
    required int remindersCount,
    dynamic nextReminder,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = isDark
        ? const Color(0xFFE8D0B2)
        : const Color(0xFFA6855B);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111112) : const Color(0xFFF3EFE9),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(
                'Personal Memory Status',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Kee is holding $memoriesCount memories and $remindersCount upcoming reminders safely on your device. Everything works offline.',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (nextReminder != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.alarm_rounded, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Next: ${nextReminder.title} (${DateFormat('EEE, MMM d @ h:mm a').format(nextReminder.scheduledAt)})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
