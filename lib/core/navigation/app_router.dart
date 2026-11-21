import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kee/core/providers/auth_provider.dart';
import 'package:kee/features/auth/presentation/login_screen.dart';
import 'package:kee/features/auth/presentation/register_screen.dart';
import 'package:kee/features/home/presentation/home_screen.dart';
import 'package:kee/features/memories/presentation/memories_screen.dart';
import 'package:kee/features/memories/presentation/memory_detail_screen.dart';
import 'package:kee/features/reminders/presentation/reminders_screen.dart';
import 'package:kee/features/recall/presentation/ask_kee_screen.dart';
import 'package:kee/features/settings/presentation/settings_screen.dart';
import 'nav_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Creates the app router with auth-aware redirect logic.
/// Must be a provider so it can read auth state for redirects.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authStatus = ref.watch(authStatusProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    redirect: (context, state) {
      final isLoading = authStatus == AuthStatus.loading;
      final isAuthenticated = authStatus == AuthStatus.authenticated;

      final currentPath = state.matchedLocation;
      final isAuthRoute =
          currentPath == '/login' || currentPath == '/register';

      // While loading (checking stored token), don't redirect
      if (isLoading) return null;

      // Not authenticated → force to login (unless already on auth route)
      if (!isAuthenticated && !isAuthRoute) {
        return '/login';
      }

      // Authenticated but on auth route → go to home
      if (isAuthenticated && isAuthRoute) {
        return '/home';
      }

      // No redirect needed
      return null;
    },
    routes: [
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

      // ─── Main App Shell (authenticated) ─────────────
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

          // Branch 2: Memories
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/memories',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: MemoriesScreen(),
                ),
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
            ],
          ),

          // Branch 3: Reminders
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reminders',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: RemindersScreen(),
                ),
              ),
            ],
          ),

          // Branch 4: Ask Kee
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

          // Branch 5: Settings
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
