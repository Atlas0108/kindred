import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../app/view_as_controller.dart';
import '../core/models/user_profile.dart';

/// Where this control is placed (affects padding and collapsed-rail icon mode).
enum ViewAsIdentityPlacement {
  /// Centered below the profile avatar (profile tab); matches header typography.
  profileBelowAvatar,

  /// Inside [NavigationRail.leading] when the rail is extended.
  railExtended,

  /// Narrow navigation rail: compact chevron control, same menu.
  railCollapsed,
}

/// Switch account via a tappable row: serif display name + chevron (no default dropdown field chrome).
class ViewAsIdentityMenu extends StatelessWidget {
  const ViewAsIdentityMenu({
    super.key,
    this.placement = ViewAsIdentityPlacement.railExtended,
  });

  final ViewAsIdentityPlacement placement;

  static String _currentLabel({
    required String? actingUid,
    required String selfLabel,
    required List<UserProfile> orgs,
  }) {
    if (actingUid == null) return selfLabel;
    for (final p in orgs) {
      if (p.uid == actingUid) return p.publicDisplayLabel;
    }
    return selfLabel;
  }

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) return const SizedBox.shrink();

    return Consumer<ViewAsController>(
      builder: (context, viewAs, _) {
        final orgs = viewAs.staffOrganizations;
        if (orgs.isEmpty) return const SizedBox.shrink();

        final selfLabel = auth.displayName?.trim().isNotEmpty == true
            ? auth.displayName!.trim()
            : 'Personal account';

        final currentLabel = _currentLabel(
          actingUid: viewAs.actingOrganizationUid,
          selfLabel: selfLabel,
          orgs: orgs,
        );

        // Use the signed-in uid for "personal" — not `null`. PopupMenuButton often
        // skips onSelected when value is null (notably on web), so switching back broke.
        final personalValue = auth.uid;
        final items = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: personalValue,
            child: Text(selfLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const PopupMenuDivider(),
          ...orgs.map(
            (p) => PopupMenuItem<String>(
              value: p.uid,
              child: Text(p.publicDisplayLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ];

        void onSelect(String v) => viewAs.setActingOrganizationUid(v);

        if (placement == ViewAsIdentityPlacement.railCollapsed) {
          return PopupMenuButton<String>(
            tooltip: 'Switch account',
            padding: EdgeInsets.zero,
            onSelected: onSelect,
            itemBuilder: (context) => items,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }

        final onSurface = Theme.of(context).colorScheme.onSurface;
        final chevronColor = Theme.of(context).colorScheme.onSurfaceVariant;

        if (placement == ViewAsIdentityPlacement.profileBelowAvatar) {
          final serif = GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: onSurface,
            height: 1.15,
          );
          final maxW = MediaQuery.sizeOf(context).width - 64;
          return Center(
            child: PopupMenuButton<String>(
              tooltip: 'Switch account',
              padding: EdgeInsets.zero,
              splashRadius: 28,
              onSelected: onSelect,
              itemBuilder: (context) => items,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW.clamp(0, 360)),
                      child: Text(
                        currentLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: serif,
                      ),
                    ),
                    Icon(Icons.expand_more, size: 26, color: chevronColor),
                  ],
                ),
              ),
            ),
          );
        }

        final serif = GoogleFonts.playfairDisplay(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface,
          height: 1.2,
        );

        return PopupMenuButton<String>(
          tooltip: 'Switch account',
          padding: EdgeInsets.zero,
          splashRadius: 24,
          onSelected: onSelect,
          itemBuilder: (context) => items,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    currentLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: serif,
                  ),
                ),
                Icon(Icons.expand_more, size: 22, color: chevronColor),
              ],
            ),
          ),
        );
      },
    );
  }
}
