import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/view_as_controller.dart';
import '../../core/models/direct_conversation.dart';
import '../../core/services/messaging_service.dart';
import 'chat_screen.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  static String _conversationInitial(String title) {
    final t = title.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const Scaffold(body: Center(child: Text('Sign in to view messages.')));
    }

    final viewAs = context.watch<ViewAsController>();
    final myUid = viewAs.effectiveProfileUid;
    if (myUid.isEmpty) {
      return const Scaffold(body: Center(child: Text('Sign in to view messages.')));
    }

    final svc = context.read<MessagingService>();
    final dateFmt = DateFormat.MMMd();
    final timeFmt = DateFormat.jm();

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: StreamBuilder<List<DirectConversation>>(
        stream: svc.myConversationsStream(inboxUid: myUid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      'Couldn’t load conversations',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No conversations yet',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open someone’s profile and tap Message to start a chat.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Conversations',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final other = c.otherParticipantId(myUid);
                    final title = c.displayNameForUser(other) ?? 'Neighbor';
                    final preview =
                        c.lastMessageText.trim().isEmpty ? 'No messages yet' : c.lastMessageText;
                    final t = c.updatedAt.toLocal();
                    final sub = DateTime.now().difference(t).inHours < 24
                        ? timeFmt.format(t)
                        : dateFmt.format(t);
                    final initial = _conversationInitial(title);
                    final unread = c.hasUnreadFor(myUid);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: unread ? theme.colorScheme.primaryContainer : null,
                        child: Text(initial),
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                          color: unread
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            sub,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: unread
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(height: 4),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE53935),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => context.push(
                        '/chat/${c.id}',
                        extra: ChatScreenRouteExtra(
                          otherUserId: other,
                          otherDisplayName: title,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
