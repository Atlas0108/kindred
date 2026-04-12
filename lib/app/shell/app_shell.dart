import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/connection_service.dart';
import '../../core/services/messaging_service.dart';
import '../../widgets/pending_connection_requests_badge.dart';
import '../responsive/breakpoints.dart';

/// Responsive shell: bottom [NavigationBar] on narrow viewports, [NavigationRail] on wide.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  static const _home = NavigationDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home),
    label: 'Home',
  );
  static const _post = NavigationDestination(
    icon: Icon(Icons.edit_note_outlined),
    selectedIcon: Icon(Icons.edit_note),
    label: 'Post',
  );
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kWideLayoutBreakpoint;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: width >= 1100,
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: navigationShell.goBranch,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Kindred',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.edit_note_outlined),
                  selectedIcon: Icon(Icons.edit_note),
                  label: Text('Post'),
                ),
                NavigationRailDestination(
                  icon: _InboxNavIcon(selected: false, showUnreadBadge: true),
                  selectedIcon: _InboxNavIcon(selected: true, showUnreadBadge: false),
                  label: Text('Inbox'),
                ),
                NavigationRailDestination(
                  icon: _ProfileNavIcon(selected: false, showPendingBadge: true),
                  selectedIcon: _ProfileNavIcon(selected: true, showPendingBadge: false),
                  label: Text('Profile'),
                ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: navigationShell,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          _home,
          _post,
          NavigationDestination(
            icon: _InboxNavIcon(selected: false, showUnreadBadge: true),
            selectedIcon: _InboxNavIcon(selected: true, showUnreadBadge: false),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: _ProfileNavIcon(selected: false, showPendingBadge: true),
            selectedIcon: _ProfileNavIcon(selected: true, showPendingBadge: false),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Inbox tab icon with unread count badge (same red pill as profile connection requests).
class _InboxNavIcon extends StatelessWidget {
  const _InboxNavIcon({
    required this.selected,
    this.showUnreadBadge = true,
  });

  final bool selected;
  /// When false (selected tab), hide the badge while Inbox is active.
  final bool showUnreadBadge;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<MessagingService>();
    return SizedBox(
      width: 36,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(
            selected ? Icons.inbox : Icons.inbox_outlined,
            size: 24,
          ),
          if (showUnreadBadge)
            Positioned(
              top: -2,
              right: -4,
              child: StreamBuilder<int>(
                stream: svc.unreadInboxCountStream(),
                builder: (context, snap) {
                  final n = snap.data ?? 0;
                  if (n <= 0) return const SizedBox.shrink();
                  return PendingConnectionRequestsBadge(count: n);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Profile tab icon with pending connection requests badge (top-right over icon).
class _ProfileNavIcon extends StatelessWidget {
  const _ProfileNavIcon({
    required this.selected,
    this.showPendingBadge = true,
  });

  final bool selected;
  /// When false (selected tab icon), hide the requests badge while Profile is active.
  final bool showPendingBadge;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ConnectionService>();
    return SizedBox(
      width: 36,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(
            selected ? Icons.person : Icons.person_outline,
            size: 24,
          ),
          if (showPendingBadge)
            Positioned(
              top: -2,
              right: -4,
              child: StreamBuilder<int>(
                stream: svc.incomingRequestCountStream(),
                builder: (context, snap) {
                  final n = snap.data ?? 0;
                  if (n <= 0) return const SizedBox.shrink();
                  return PendingConnectionRequestsBadge(count: n);
                },
              ),
            ),
        ],
      ),
    );
  }
}
