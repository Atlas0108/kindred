import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/saved_posts_service.dart';

/// Bookmark control for feed cards; hidden when signed out. Stops tap propagation to the card.
class PostSaveButton extends StatelessWidget {
  const PostSaveButton({super.key, required this.contentId});

  final String contentId;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final svc = context.read<SavedPostsService>();

    return StreamBuilder<Set<String>>(
      stream: svc.savedIdsStream(),
      builder: (context, snap) {
        final saved = snap.data?.contains(contentId) ?? false;
        return Material(
          color: Colors.white.withValues(alpha: 0.94),
          elevation: 1,
          shadowColor: Colors.black26,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => svc.toggleSave(contentId),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                saved ? Icons.bookmark : Icons.bookmark_border,
                size: 22,
                color: saved ? const Color(0xFF4A6354) : const Color(0xFF6B7280),
              ),
            ),
          ),
        );
      },
    );
  }
}
