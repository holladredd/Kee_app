import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/intelligence/unified_chat_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/voice/assistant_state.dart';
import '../../../core/voice/voice_assistant_controller.dart';
import '../../../core/widgets/kee_logo.dart';
import '../../../core/widgets/kee_onboarding_sheet.dart';
import '../../../core/widgets/kee_voice_orb.dart';
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

  void _handleSubmitQuickChat(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    _quickInputController.clear();
    ref.read(unifiedChatProvider.notifier).sendMessage(query);
    context.go('/ask-kee');
  }

  void _showAppMenu(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color accentColor,
  ) {
    final auth = ref.read(authProvider);
    final user = auth.user;
    final displayName = user != null && user.email.contains('@')
        ? user.email.split('@').first
        : (user?.email ?? 'Kee User');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'K';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF14120E) : const Color(0xFFFBF8F4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // User Profile Header Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1A14) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: accentColor.withValues(alpha: 0.15),
                        child: Text(
                          initial,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? 'Logged In',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Menu Navigation Options
                _buildMenuItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Chat with Kee',
                  subtitle: 'Open the unified personal conversation',
                  color: accentColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/ask-kee');
                  },
                ),
                _buildMenuItem(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Memory Vault',
                  subtitle: 'Review and search stored facts & preferences',
                  color: accentColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/memories');
                  },
                ),
                _buildMenuItem(
                  icon: Icons.alarm_rounded,
                  title: 'Reminders & Tasks',
                  subtitle: 'Scheduled notifications and to-dos',
                  color: accentColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/reminders');
                  },
                ),
                _buildMenuItem(
                  icon: Icons.settings_outlined,
                  title: 'Settings & Voice',
                  subtitle: 'Hands-free "Hi Kee" / "What\'s up K", theme & sound',
                  color: accentColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go('/settings');
                  },
                ),
                const Divider(height: 24),
                _buildMenuItem(
                  icon: Icons.logout_rounded,
                  title: 'Sign Out',
                  subtitle: 'End your current session',
                  color: theme.colorScheme.error,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color == Theme.of(context).colorScheme.error ? color : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
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

    // Safely read voice state
    VoiceAssistantState? voiceState;
    try {
      voiceState = ref.watch(voiceAssistantProvider);
    } catch (e) {
      debugPrint('[HomeScreen] Voice provider unavailable: $e');
    }
    final isVoiceAvailable = voiceState != null;

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

                // ─── 1. Brand Header & Top Menu Button ────────
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

                    // Top Menu Button to access Settings, Profile, Logout, etc.
                    IconButton(
                      icon: const Icon(Icons.menu_rounded, size: 28),
                      tooltip: 'Menu',
                      onPressed: () => _showAppMenu(context, theme, isDark, accentColor),
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

                // ─── 3. Chat Section at Top of Home (Takes user to Chat page) ───
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF14120E) : const Color(0xFFFBF8F4),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(
                      color: (voiceState?.isListening ?? false)
                          ? accentColor
                          : (isDark ? const Color(0xFF2E271F) : const Color(0xFFE2D6C5)),
                      width: (voiceState?.isListening ?? false) ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.45)
                            : Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Tapping the card directly takes the user to the single chat page
                      InkWell(
                        onTap: () {
                          if (isVoiceAvailable) {
                            try {
                              final voiceCtrl = ref.read(voiceAssistantProvider.notifier);
                              if (!(voiceState?.isListening ?? false) && !(voiceState?.isSpeaking ?? false)) {
                                voiceCtrl.startListening();
                              }
                            } catch (_) {}
                          }
                          context.go('/ask-kee');
                        },
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              if (voiceState != null)
                                KeeVoiceOrb(
                                  state: voiceState.state,
                                  soundLevel: voiceState.soundLevel,
                                  size: 48,
                                )
                              else
                                const KeeLogo(size: 48),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Chat with Kee',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: accentColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            (voiceState?.isHandsFreeEnabled ?? false) ? '"Hi Kee" / "What\'s up K"' : 'AI Chat',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: accentColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (voiceState?.isListening ?? false)
                                          ? 'Listening... tap to open chat'
                                          : 'Tap to open the unified personal conversation',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: accentColor),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: theme.colorScheme.outline.withValues(alpha: 0.3)),
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
                                  hintText: 'Ask or remember anything...',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: (val) => _handleSubmitQuickChat(val),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send_rounded, size: 18),
                              tooltip: 'Open Chat',
                              color: accentColor,
                              onPressed: () => _handleSubmitQuickChat(_quickInputController.text),
                            ),
                          ],
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
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'Capture an idea',
                  subtitle: '"I have an idea for an app that connects farmers to buyers"',
                  onTap: () => _handleSubmitQuickChat('I have an idea for an app that connects farmers to buyers'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildPromptTile(
                  context: context,
                  icon: Icons.alarm_rounded,
                  title: 'Schedule a smart reminder',
                  subtitle: '"Remind me to call David tomorrow at 3 PM"',
                  onTap: () => _handleSubmitQuickChat('Remind me to call David tomorrow at 3 PM'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildPromptTile(
                  context: context,
                  icon: Icons.psychology_outlined,
                  title: 'Remember a preference',
                  subtitle: '"Remember that I prefer morning meetings over afternoon ones"',
                  onTap: () => _handleSubmitQuickChat('Remember that I prefer morning meetings over afternoon ones'),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ─── 5. Intelligence Status Cards ──────────────
                memoriesAsync.when(
                  data: (memories) {
                    return remindersAsync.when(
                      data: (reminders) {
                        final upcoming = reminders.where((r) => r.isEnabled && r.scheduledAt.isAfter(DateTime.now())).toList()
                          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

                        return _buildStatusCard(
                          context,
                          memoriesCount: memories.length,
                          remindersCount: reminders.length,
                          nextReminder: upcoming.isNotEmpty ? upcoming.first : null,
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
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
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.north_west_rounded,
              size: 14,
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
          color: isDark ? const Color(0xFF262626) : const Color(0xFFE2DCD4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'KNOWLEDGE VAULT OVERVIEW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: accentColor,
                ),
              ),
              InkWell(
                onTap: () => context.push('/memories'),
                child: Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  label: 'Memories Saved',
                  count: memoriesCount.toString(),
                  icon: Icons.auto_awesome_rounded,
                  theme: theme,
                  accentColor: accentColor,
                  onTap: () => context.push('/memories'),
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              Expanded(
                child: _buildMetricItem(
                  label: 'Active Reminders',
                  count: remindersCount.toString(),
                  icon: Icons.alarm_rounded,
                  theme: theme,
                  accentColor: accentColor,
                  onTap: () => context.push('/reminders'),
                ),
              ),
            ],
          ),
          if (nextReminder != null) ...[
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Icon(Icons.upcoming_rounded, size: 14, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Next: "${nextReminder.title}" (${DateFormat('MMM d, h:mm a').format(nextReminder.scheduledAt)})',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String count,
    required IconData icon,
    required ThemeData theme,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  count,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
