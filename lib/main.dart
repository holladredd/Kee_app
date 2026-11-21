import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/navigation/app_router.dart';
import 'core/notifications/notification_service.dart';
import 'core/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize offline local notifications
  await NotificationService.instance.initialize();

  runApp(
    const ProviderScope(
      child: KeeApp(),
    ),
  );
}

class KeeApp extends ConsumerWidget {
  const KeeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);
    final authStatus = ref.watch(authStatusProvider);

    // Show a branded splash while checking stored auth token
    if (authStatus == AuthStatus.loading) {
      return MaterialApp(
        title: 'Kee',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: const _KeeSplash(),
      );
    }

    return MaterialApp.router(
      title: 'Kee',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

/// Minimal branded splash shown while verifying auth session on startup.
class _KeeSplash extends StatelessWidget {
  const _KeeSplash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF050505) : const Color(0xFFFAF8F5);
    final textColor =
        isDark ? const Color(0xFFFBF2E6) : const Color(0xFF141312);
    final accentColor =
        isDark ? const Color(0xFFE8D0B2) : const Color(0xFFA6855B);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Kee',
              style: TextStyle(
                fontSize: 36,
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
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
