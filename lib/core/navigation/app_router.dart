import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kee/core/providers/auth_provider.dart';
import 'package:kee/features/auth/presentation/login_screen.dart';
import 'package:kee/features/auth/presentation/register_screen.dart';
import 'package:kee/features/auth/presentation/splash_screen.dart';
import 'package:kee/features/home/presentation/home_screen.dart';
import 'package:kee/features/memories/presentation/memories_screen.dart';
import 'package:kee/features/memories/presentation/memory_detail_screen.dart';
import 'package:kee/features/reminders/presentation/reminders_screen.dart';
import 'package:kee/features/recall/presentation/ask_kee_screen.dart';
import 'package:kee/features/settings/presentation/settings_screen.dart';
import 'nav_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Listenable that notifies GoRouter to re-evaluate its redirect logic
/// whenever the Riverpod auth state changes.
class AuthRouterListenable extends ChangeNotifier {
  final Ref _ref;

  AuthRouterListenable(this._ref) {
    _ref.listen<AuthState>(
      authProvider,
      (previous, next) {
        if (previous?.status != next.status) {
          notifyListeners();
        }
      },
    );
  }
}

final authRouterListenableProvider = Provider<AuthRouterListenable>((ref) {
  return AuthRouterListenable(ref);
});

/// Creates the app router with conversation-first primary navigation:
/// 1. Home
/// 2. Ask Kee
/// 3. Settings
/// (Memories and Reminders are preserved as accessible sub-routes)
final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = ref.watch(authRouterListenableProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: listenable,
    initialLocation: '/splash',
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final status = authState.status;

      final matchedLocation = state.matchedLocation;
      final isAuthRoute =
          matchedLocation == '/login' || matchedLocation == '/register';
      final isSplash = matchedLocation == '/splash';

      // 1. Initializing — stay on splash while checking token
      if (status == AuthStatus.initializing) {
        return isSplash ? null : '/splash';
      }

      // 2. Unauthenticated — force to login if not already on an auth screen
      if (status == AuthStatus.unauthenticated) {
        return isAuthRoute ? null : '/login';
      }

      // 3. Authenticated — redirect away from splash, login, or register to home
      if (status == AuthStatus.authenticated) {
        if (isAuthRoute || isSplash) {
          return '/home';
        }
        return null;
      }

      return null;
    },
    routes: [
      // ─── Splash Screen ──────────────────────────────
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SplashScreen(),
        ),
      ),

      // ─── Auth Routes (outside the shell) ────────────
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: RegisterScreen(),
        ),
      ),

      // ─── Preserved Data Management Sub-routes ───────
      GoRoute(
        path: '/memories',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MemoriesScreen(),
        routes: [
          GoRoute(
            path: 'detail/:id',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return MemoryDetailScreen(memoryId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/reminders',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RemindersScreen(),
      ),

      // ─── Main Conversation-First Shell (3 Tabs) ─────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return NavShell(navigationShell: navigationShell);
        },
        branches: [
          // Branch 1: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomeScreen(),
                ),
              ),
            ],
          ),

          // Branch 2: Ask Kee (Primary Conversation Experience)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ask-kee',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: AskKeeScreen(),
                ),
              ),
            ],
          ),

          // Branch 3: Settings (Controls & Privacy Vault)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: SettingsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
