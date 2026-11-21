import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kee/core/constants/app_spacing.dart';
import 'package:kee/core/providers/auth_provider.dart';
import 'package:kee/core/widgets/kee_logo.dart';

/// Minimal branded splash shown only during the brief moment
/// while Kee checks local storage for a stored token.
///
/// OPTIMISTIC: This screen auto-navigates as soon as the local
/// storage check completes. If a token is found, the user goes
/// straight to /home without waiting for server validation.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeIn;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeIn = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _navigateWhenReady(AuthStatus status) {
    if (_hasNavigated) return;
    if (status == AuthStatus.initializing) return;

    _hasNavigated = true;

    // Navigate immediately — no artificial delays
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (status == AuthStatus.authenticated) {
        context.go('/home');
      } else {
        context.go('/login');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authStatus = ref.watch(authStatusProvider);

    // Navigate as soon as auth resolves
    _navigateWhenReady(authStatus);

    final bgColor = isDark ? const Color(0xFF050505) : const Color(0xFFFAF8F5);
    final textColor =
        isDark ? const Color(0xFFFBF2E6) : const Color(0xFF141312);
    final accentColor =
        isDark ? const Color(0xFFE8D0B2) : const Color(0xFFA6855B);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              KeeLogo(size: 88),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Kee',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Knowledge Extension Entity',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: accentColor,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
