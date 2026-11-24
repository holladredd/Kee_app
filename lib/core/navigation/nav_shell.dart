import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../sync/background_walker_pipeline.dart';
import '../widgets/kee_floating_assistant.dart';

/// Central navigation shell for authenticated pages.
/// Displays the current screen and pins the floating AI assistant
/// on all pages EXCEPT the dedicated chat page.
/// Authentication pages (login, register, splash) are defined outside this shell.
class NavShell extends ConsumerWidget {
  final Widget child;
  final String currentPath;

  const NavShell({
    super.key,
    required this.child,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep background walker pipeline active across all authenticated screens
    ref.watch(backgroundWalkerProvider);

    // Hide chat widget on the dedicated chat page
    final isChatPage = currentPath == '/ask-kee';

    return Scaffold(
      body: Stack(
        children: [
          child,

          // Floating AI assistant orb (shown everywhere EXCEPT on the chat page)
          if (!isChatPage)
            const KeeFloatingAssistant(),
        ],
      ),
    );
  }
}
