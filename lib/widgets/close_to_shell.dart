import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Routes rendered inside [StatefulShellRoute] (bottom nav / rail).
bool kindredIsMainShellTabPath(String path) {
  return path == '/home' ||
      path == '/post' ||
      path == '/inbox' ||
      path == '/profile';
}

/// Pops every route on the root [GoRouter] stack until only the main tab shell remains.
///
/// After a cold open or `go` from sign-in, the stack may be only `/posts/…` (or similar)
/// with nothing to pop — then we [GoRouter.go] to `/home`.
void popToMainShell(BuildContext context) {
  final router = GoRouter.of(context);
  while (router.canPop()) {
    router.pop();
  }
  if (!kindredIsMainShellTabPath(router.state.uri.path)) {
    router.go('/home');
  }
}

/// Back from a full-screen route: pop if there is a prior page, otherwise go home.
void kindredPopOrGoHome(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/home');
  }
}

/// App bar action (top right): closes the full pushed stack above the tab shell.
class CloseToShellIconButton extends StatelessWidget {
  const CloseToShellIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Close',
      onPressed: () => popToMainShell(context),
    );
  }
}
