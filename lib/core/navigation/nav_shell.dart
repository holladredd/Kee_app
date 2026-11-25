import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation shell for authenticated pages.
/// When Kee is open in the foreground, the normal application interface
/// is displayed cleanly with NO floating assistant widget covering the screens.
/// The floating widget is exclusively used outside Kee when summoned via wake-word.
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
    return Scaffold(
      body: child,
    );
  }
}
