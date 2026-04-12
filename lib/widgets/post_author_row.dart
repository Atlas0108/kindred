import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/models/user_profile.dart';
import '../core/services/user_profile_service.dart';

/// Same blue as profile “Verified” (no text on cards).
const kKindredVerifiedBadgeBlue = Color(0xFF2563EB);

/// Avatar + author line; label uses live `users/{authorId}` display name when available
/// ([authorName] is only a fallback). Tap opens [`/u/{authorId}`] except for the signed-in user.
class PostAuthorTapRow extends StatelessWidget {
  const PostAuthorTapRow({
    super.key,
    required this.authorId,
    required this.authorName,
    this.prefix = 'Shared by ',
    this.textStyle,
    this.avatarRadius = 18,
    this.iconColor,
    this.placeholderBackgroundColor,
    this.enableProfileTap = true,
    this.showVerifiedBadge = false,
    this.verifiedIconSize = 14,
  });

  final String authorId;
  final String authorName;
  final String prefix;
  final TextStyle? textStyle;
  final double avatarRadius;
  final Color? iconColor;
  final Color? placeholderBackgroundColor;

  /// When false, the row is display-only (e.g. post cards on the home feed).
  final bool enableProfileTap;

  /// Compact [Icons.verified_rounded] after the name (feed post cards).
  final bool showVerifiedBadge;
  final double verifiedIconSize;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  void _openProfile(BuildContext context) {
    if (authorId.isEmpty) return;
    context.push('/u/$authorId');
  }

  Widget _initialsPlate(String name, Color bg, Color ic) {
    return ColoredBox(
      color: bg,
      child: Center(
        child: Text(
          _initials(name),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: avatarRadius * 0.85,
            fontWeight: FontWeight.w600,
            color: ic,
            height: 1,
          ),
        ),
      ),
    );
  }

  /// Fixed [d]×[d] content clipped to a circle (avoids square placeholders overlapping the ring).
  Widget _clippedAvatar({
    required double d,
    required Color bg,
    required Color ic,
    required String name,
    String? imageUrl,
  }) {
    Widget inner;
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      inner = Image.network(
        url,
        width: d,
        height: d,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return ColoredBox(
            color: bg,
            child: Center(
              child: SizedBox(
                width: avatarRadius * 0.8,
                height: avatarRadius * 0.8,
                child: CircularProgressIndicator(strokeWidth: 2, color: ic),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _initialsPlate(name, bg, ic),
      );
    } else {
      inner = _initialsPlate(name, bg, ic);
    }

    return ClipOval(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: d, height: d, child: inner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<UserProfileService>();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isSelf = myUid != null && authorId == myUid;
    final tappable = enableProfileTap && authorId.isNotEmpty && !isSelf;

    final defaultStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w500,
          fontSize: 14,
        );
    final mergedStyle = textStyle ?? defaultStyle;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tappable ? () => _openProfile(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: StreamBuilder<UserProfile?>(
            stream: authorId.isEmpty
                ? Stream<UserProfile?>.value(null)
                : svc.profileStream(authorId),
            builder: (context, snap) {
              final profile = snap.data;
              final fromProfile = profile?.publicDisplayLabel.trim();
              final displayName = (fromProfile != null &&
                      fromProfile.isNotEmpty &&
                      fromProfile != 'Neighbor')
                  ? fromProfile
                  : authorName;
              final url = profile?.photoUrl?.trim();
              final bg = placeholderBackgroundColor ?? Colors.grey.shade300;
              final ic = iconColor ?? Colors.grey.shade600;
              final d = avatarRadius * 2;
              return Row(
                children: [
                  _clippedAvatar(
                    d: d,
                    bg: bg,
                    ic: ic,
                    name: displayName,
                    imageUrl: url,
                  ),
                  SizedBox(width: avatarRadius > 16 ? 12 : 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: mergedStyle,
                        children: [
                          TextSpan(text: prefix),
                          TextSpan(
                            text: displayName,
                            style: mergedStyle?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration:
                                  tappable ? TextDecoration.underline : TextDecoration.none,
                              decorationColor: tappable
                                  ? mergedStyle.color?.withValues(alpha: 0.4)
                                  : null,
                            ),
                          ),
                          if (showVerifiedBadge)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 3),
                                child: Icon(
                                  Icons.verified_rounded,
                                  size: verifiedIconSize,
                                  color: kKindredVerifiedBadgeBlue,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
