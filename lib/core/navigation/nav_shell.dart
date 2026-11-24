import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/kee_floating_assistant.dart';

/// Navigation shell for authenticated pages that feature the floating AI assistant
/// (/home, /settings, /memories, /reminders).
/// Pages that do NOT want the floating assistant (such as the dedicated /ask-kee chat page
/// and authentication screens) are declared outside this shell.
class NavShell extends ConsumerWidget {
  final Widget child;
  final String? currentPath;

  const NavShell({
    super.key,
    required this.child,
    this.currentPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Defense in depth: do not render widget if on /ask-kee
    final isChatPage = currentPath == '/ask-kee';

    return Scaffold(
      body: Stack(
        children: [
          child,

          // Floating AI assistant orb (pinned on shell pages, never on chat page)
          if (!isChatPage)
            const KeeFloatingAssistant(),
        ],
      ),
    );
  }
}
