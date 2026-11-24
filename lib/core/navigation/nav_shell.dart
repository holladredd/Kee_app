import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../voice/assistant_state.dart';
import '../voice/voice_assistant_controller.dart';
import '../widgets/kee_floating_assistant.dart';

class NavShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const NavShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Safely watch the voice provider — if it fails to initialize (e.g. on web
    // where platform plugins may not load), fall back gracefully.
    VoiceAssistantState? assistant;
    try {
      assistant = ref.watch(voiceAssistantProvider);
    } catch (e) {
      debugPrint('[NavShell] Voice provider unavailable: $e');
    }

    final showFloatingAssistant = assistant != null &&
        (assistant.isExpanded || navigationShell.currentIndex != 1);

    return Scaffold(
      body: Stack(
        children: [
          navigationShell,

          // Global floating assistant orb (shown outside Ask Kee screen, or whenever expanded)
          if (showFloatingAssistant)
            const KeeFloatingAssistant(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'Ask Kee',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
