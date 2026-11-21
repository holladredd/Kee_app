import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kee/core/providers/auth_provider.dart';

/// Minimal branded splash screen showing ONLY the official Kee logo image (no text).
/// Automatically navigates once the session verification completes.
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

    _navigateWhenReady(authStatus);

    final bgColor = isDark ? const Color(0xFF050505) : const Color(0xFFFAF8F5);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Image.asset(
            isDark
                ? 'assets/logo/Kee Logo on Dark Canvas.png'
                : 'assets/logo/kee_logo_mark_light.png',
            width: 140,
            height: 140,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
