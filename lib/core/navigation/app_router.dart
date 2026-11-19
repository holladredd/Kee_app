import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/memories/presentation/memories_screen.dart';
import '../../features/memories/presentation/memory_detail_screen.dart';
import '../../features/reminders/presentation/reminders_screen.dart';
import '../../features/recall/presentation/ask_kee_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import 'nav_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
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
