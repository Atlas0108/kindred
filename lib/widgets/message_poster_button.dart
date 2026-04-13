import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app/view_as_controller.dart';
import '../core/services/messaging_service.dart';
import '../features/inbox/chat_screen.dart';

/// Square control with rounded corners; opens a direct chat with the post author.
class MessagePosterButton extends StatelessWidget {
  const MessagePosterButton({
    super.key,
    required this.authorId,
    required this.authorName,
  });

  final String authorId;
  final String authorName;

  void _onTap(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to send a message')),
      );
      return;
    }
    final myUid = context.read<ViewAsController>().effectiveProfileUid;
    if (myUid.isEmpty || authorId.isEmpty || authorId == myUid) return;

    final id = MessagingService.conversationIdForPair(myUid, authorId);
    context.push(
      '/chat/$id',
      extra: ChatScreenRouteExtra(otherUserId: authorId, otherDisplayName: authorName),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (authorId.isEmpty) return const SizedBox.shrink();
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const SizedBox.shrink();
    final myUid = context.watch<ViewAsController>().effectiveProfileUid;
    if (authorId == myUid) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Message',
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _onTap(context),
          borderRadius: BorderRadius.circular(10),
          splashColor: scheme.onPrimary.withValues(alpha: 0.16),
          highlightColor: scheme.onPrimary.withValues(alpha: 0.08),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 22,
              color: scheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
