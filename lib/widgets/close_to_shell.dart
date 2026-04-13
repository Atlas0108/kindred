import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pops every route on the root [GoRouter] stack until only the main tab shell remains.
void popToMainShell(BuildContext context) {
  final router = GoRouter.of(context);
  while (router.canPop()) {
    router.pop();
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
