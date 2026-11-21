import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_spacing.dart';
import 'kee_logo.dart';

class KeeOnboardingSheet extends StatelessWidget {
  final bool isReview;

  const KeeOnboardingSheet({super.key, this.isReview = false});

  static const String _storageKey = 'kee_has_seen_onboarding_v1';
  static const _storage = FlutterSecureStorage();

  static Future<void> checkAndShow(BuildContext context) async {
    try {
      final seen = await _storage.read(key: _storageKey);
      if (seen != 'true' && context.mounted) {
        show(context, isReview: false);
      }
    } catch (_) {}
  }

  static Future<void> show(BuildContext context, {bool isReview = false}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => KeeOnboardingSheet(isReview: isReview),
    );
  }

  Future<void> _markSeen(BuildContext context) async {
    try {
      await _storage.write(key: _storageKey, value: 'true');
    } catch (_) {}
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
        border: Border.all(
          color: theme.colorScheme.outline,
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Minimal handle bar
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Kee Monogram Logo
                      const KeeLogo(size: 68),
                      const SizedBox(height: AppSpacing.md),

                      // Brand Header
                      Text(
                        'Kee',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'K.E.E. · Knowledge Extension Entity',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: isDark ? const Color(0xFFE8D0B2) : const Color(0xFFA6855B),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),

                      // Tagline badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          border: Border.all(color: theme.colorScheme.outline, width: 0.8),
                        ),
                        child: Text(
                          'Your memory. Extended.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Mission Statement
                      Text(
                        'Meet Kee, your Knowledge Extension Entity. A personal intelligence that helps you capture what matters, remember what you forget, and retrieve information whenever you need it.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // 3 Core Pillars
                      _buildPillarTile(
                        context: context,
                        icon: Icons.edit_note_rounded,
                        title: 'Capture What Matters',
                        description:
                            'Capture thoughts, tasks, preferences, and voice recordings with zero mental friction.',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _buildPillarTile(
                        context: context,
                        icon: Icons.alarm_on_rounded,
                        title: 'Remember What You Forget',
                        description:
                            'Deterministic reminders and task tracking ensure commitments and promises never slip.',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _buildPillarTile(
                        context: context,
                        icon: Icons.psychology_rounded,
                        title: 'Natural Offline Recall',
                        description:
                            'Ask Kee anything in natural conversation. Instant answers grounded strictly in your real memories.',
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Privacy guarantee
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '100% Offline · Private On-Device · No External APIs',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),

              // Get Started CTA
              ElevatedButton(
                onPressed: () => _markSeen(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                child: Text(
                  isReview ? 'Close' : 'Get Started with Kee',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPillarTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: theme.colorScheme.outline, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: theme.colorScheme.outline, width: 0.8),
            ),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
