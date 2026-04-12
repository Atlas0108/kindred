import 'package:flutter/material.dart';

import '../core/models/post_kind.dart';

/// Matches home feed list styling: soft green (offer) / pink–lavender (request).
Color postKindIconBadgeBackground(PostKind kind) {
  return switch (kind) {
    PostKind.helpOffer => const Color(0xFFE8F3EB),
    PostKind.helpRequest => const Color(0xFFF3E8F7),
    PostKind.communityEvent => const Color(0xFFE8F3EB),
  };
}

/// Short headline above titles on feed and detail (OFFER / REQUEST / EVENT).
String postKindListHeadline(PostKind kind) {
  return switch (kind) {
    PostKind.helpOffer => 'OFFER',
    PostKind.helpRequest => 'REQUEST',
    PostKind.communityEvent => 'EVENT',
  };
}

/// Rounded icon tile used on the home feed and post detail (list-style chrome).
class PostKindIconBadge extends StatelessWidget {
  const PostKindIconBadge({super.key, required this.kind, this.compact = false});

  final PostKind kind;
  final bool compact;

  static const _iconColor = Color(0xFF4A6354);

  IconData get _icon {
    return switch (kind) {
      PostKind.helpOffer => Icons.volunteer_activism_outlined,
      PostKind.helpRequest => Icons.help_outline_rounded,
      PostKind.communityEvent => Icons.event_note_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 22.0 : 30.0;
    final padH = compact ? 12.0 : 16.0;
    final padV = compact ? 10.0 : 14.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: postKindIconBadgeBackground(kind),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: Icon(_icon, size: iconSize, color: _iconColor),
      ),
    );
  }
}
