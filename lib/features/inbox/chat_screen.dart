import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/direct_conversation.dart';
import '../../core/services/messaging_service.dart';
import '../../core/services/user_profile_service.dart';

/// Passed via [GoRouterState.extra] when opening chat from a profile (optimistic navigation).
class ChatScreenRouteExtra {
  const ChatScreenRouteExtra({
    required this.otherUserId,
    required this.otherDisplayName,
  });

  final String otherUserId;
  final String otherDisplayName;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.routeExtra,
  });

  final String conversationId;
  final ChatScreenRouteExtra? routeExtra;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  bool _sending = false;
  Future<void>? _ensureFuture;

  @override
  void initState() {
    super.initState();
    if (widget.routeExtra != null) {
      _ensureFuture = _ensureConversation();
    }
  }

  Future<void> _ensureConversation() async {
    final extra = widget.routeExtra;
    if (extra == null) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || !mounted) return;
    final msg = context.read<MessagingService>();
    final profileSvc = context.read<UserProfileService>();
    try {
      final myProfile = await profileSvc.fetchProfile(me.uid);
      if (!mounted) return;
      final myName = myProfile?.publicDisplayLabel.trim().isNotEmpty == true &&
              myProfile!.publicDisplayLabel != 'Neighbor'
          ? myProfile.publicDisplayLabel
          : (me.displayName?.trim().isNotEmpty == true ? me.displayName!.trim() : 'Neighbor');
      await msg.ensureDirectConversation(
        otherUserId: extra.otherUserId,
        otherDisplayName: extra.otherDisplayName,
        myDisplayName: myName,
      );
    } on Object catch (e) {
      if (mounted) {
        final detail = e is FirebaseException ? '${e.code}: ${e.message}' : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start chat: $detail')),
        );
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final body = _text.text;
    if (body.trim().isEmpty) return;
    if (_ensureFuture != null) {
      try {
        await _ensureFuture!;
      } on Object catch (e) {
        if (mounted) {
          final detail = e is FirebaseException ? '${e.code}: ${e.message}' : '$e';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send: $detail')),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final msg = context.read<MessagingService>();
    setState(() => _sending = true);
    _text.clear();
    try {
      await msg.sendMessage(widget.conversationId, body);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
        _text.text = body;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final timeFmt = DateFormat.jm();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: StreamBuilder<DirectConversation?>(
          stream: context.read<MessagingService>().conversationStream(widget.conversationId),
          builder: (context, snap) {
            final conv = snap.data;
            if (myUid == null) return const Text('Chat');
            if (conv != null) {
              final other = conv.otherParticipantId(myUid);
              final name = conv.displayNameForUser(other) ?? 'Neighbor';
              return Text(name);
            }
            final optimistic = widget.routeExtra?.otherDisplayName.trim();
            if (optimistic != null && optimistic.isNotEmpty) {
              return Text(optimistic);
            }
            return const Text('Chat');
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: context.read<MessagingService>().messagesStream(widget.conversationId),
              builder: (context, snap) {
                final messages = snap.data ?? [];
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hello to start the conversation.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                final rev = messages.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: rev.length,
                  itemBuilder: (context, i) {
                    final m = rev[i];
                    final mine = m.senderId == myUid;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.text, style: Theme.of(context).textTheme.bodyLarge),
                            const SizedBox(height: 4),
                            Text(
                              timeFmt.format(m.createdAt.toLocal()),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message…',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
