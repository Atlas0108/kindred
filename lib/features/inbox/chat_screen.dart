import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/view_as_controller.dart';
import '../../widgets/close_to_shell.dart';
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
  /// After [ensureDirectConversation] runs for profile/post → chat navigation.
  bool _conversationEnsured = false;
  StreamSubscription<DirectConversation?>? _conversationReadSub;
  /// `${conversationId}|${effectiveProfileUid}` so read receipts follow View As.
  String? _readWatchKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewAs = context.watch<ViewAsController>();
    final myUid = viewAs.effectiveProfileUid;
    final key = '${widget.conversationId}|$myUid';
    if (_readWatchKey == key) return;
    _readWatchKey = key;
    _conversationReadSub?.cancel();
    final svc = context.read<MessagingService>();
    _conversationReadSub = svc.conversationStream(widget.conversationId).listen((conv) {
      if (!mounted || conv == null) return;
      if (myUid.isEmpty || !conv.hasUnreadFor(myUid)) return;
      unawaited(svc.markConversationRead(widget.conversationId, readerUid: myUid));
    });
  }

  /// Creates `conversations/{id}` only when sending the first message (not on open).
  Future<void> _ensureConversation() async {
    final extra = widget.routeExtra;
    if (extra == null) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || !mounted) throw StateError('Not signed in');
    final myUid = context.read<ViewAsController>().effectiveProfileUid;
    if (myUid.isEmpty) throw StateError('Not signed in');
    final msg = context.read<MessagingService>();
    final profileSvc = context.read<UserProfileService>();
    final myProfile = await profileSvc.fetchProfile(myUid);
    if (!mounted) return;
    final myName = myProfile?.publicDisplayLabel.trim().isNotEmpty == true &&
            myProfile!.publicDisplayLabel != 'Neighbor'
        ? myProfile.publicDisplayLabel
        : (me.displayName?.trim().isNotEmpty == true ? me.displayName!.trim() : 'Neighbor');
    await msg.ensureDirectConversation(
      myUserId: myUid,
      otherUserId: extra.otherUserId,
      otherDisplayName: extra.otherDisplayName,
      myDisplayName: myName,
    );
  }

  @override
  void dispose() {
    _conversationReadSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final body = _text.text;
    if (body.trim().isEmpty) return;

    setState(() => _sending = true);
    try {
      if (widget.routeExtra != null && !_conversationEnsured) {
        try {
          await _ensureConversation();
        } on Object catch (e) {
          if (mounted) {
            final detail = e is FirebaseException ? '${e.code}: ${e.message}' : '$e';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not send: $detail')),
            );
          }
          return;
        }
        if (!mounted) return;
        _conversationEnsured = true;
      }

      final msg = context.read<MessagingService>();
      final senderUid = context.read<ViewAsController>().effectiveProfileUid;
      _text.clear();
      try {
        await msg.sendMessage(
          widget.conversationId,
          body,
          senderId: senderUid.isEmpty ? null : senderUid,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
          _text.text = body;
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewAs = context.watch<ViewAsController>();
    final myUid = viewAs.effectiveProfileUid;
    final timeFmt = DateFormat.jm();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: const [CloseToShellIconButton()],
        title: StreamBuilder<DirectConversation?>(
          stream: context.read<MessagingService>().conversationStream(widget.conversationId),
          builder: (context, snap) {
            final conv = snap.data;
            if (myUid.isEmpty) return const Text('Chat');
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
