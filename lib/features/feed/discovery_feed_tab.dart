import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/event_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/utils/event_formatting.dart';
import '../../core/utils/merge_community_events.dart';
import '../../core/constants/default_geo.dart';
import '../../widgets/post_author_row.dart';
import '../../widgets/post_save_button.dart';

class _FeedRow {
  _FeedRow.post(KindredPost p) : post = p, event = null, sortTime = p.createdAt;
  _FeedRow.event(CommunityEvent e) : post = null, event = e, sortTime = e.startsAt;

  final KindredPost? post;
  final CommunityEvent? event;
  final DateTime sortTime;
}

class DiscoveryFeedTab extends StatefulWidget {
  const DiscoveryFeedTab({super.key});

  @override
  State<DiscoveryFeedTab> createState() => _DiscoveryFeedTabState();
}

class _DiscoveryFeedTabState extends State<DiscoveryFeedTab> {
  List<KindredPost> _posts = [];
  List<CommunityEvent> _legacyEvents = [];
  StreamSubscription<List<KindredPost>>? _postSub;
  StreamSubscription<List<CommunityEvent>>? _eventSub;
  String? _discoverySubKey;

  @override
  void dispose() {
    _postSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  void _attachDiscoveryIfNeeded(GeoPoint center, int radiusMiles) {
    final key =
        '${center.latitude}_${center.longitude}_$radiusMiles';
    if (key == _discoverySubKey) return;
    _discoverySubKey = key;

    _postSub?.cancel();
    _eventSub?.cancel();

    final posts = context.read<PostService>();
    final events = context.read<EventService>();
    final radius = radiusMiles.toDouble();

    _postSub = posts.postsInRadius(center: center, radiusMiles: radius).listen((list) {
      if (mounted) setState(() => _posts = list);
    });
    _eventSub = events.eventsInRadius(center: center, radiusMiles: radius).listen((list) {
      if (mounted) setState(() => _legacyEvents = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<UserProfile?>(
      stream: context.read<UserProfileService>().profileStream(user.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        final center = profile?.homeGeoPoint ?? kDefaultGeoPoint;
        final radiusMiles = profile?.discoveryRadiusMiles ?? 25;
        _attachDiscoveryIfNeeded(center, radiusMiles);

        final helpPosts = _posts.where((p) => p.kind != PostKind.communityEvent).toList();
        final mergedEvents = mergeLegacyAndPostEventRows(_legacyEvents, _posts);
        final rows = <_FeedRow>[
          ...helpPosts.map(_FeedRow.post),
          ...mergedEvents.map(_FeedRow.event),
        ]..sort((a, b) => b.sortTime.compareTo(a.sortTime));

        return Scaffold(
          appBar: AppBar(title: const Text('Feed')),
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row.post != null) {
                return _PostTile(post: row.post!);
              }
              return _EventTile(event: row.event!);
            },
          ),
        );
      },
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final KindredPost post;

  @override
  Widget build(BuildContext context) {
    final color = switch (post.kind) {
      PostKind.helpOffer => Colors.green.shade700,
      PostKind.helpRequest => Colors.blue.shade700,
      PostKind.communityEvent => Colors.deepOrange.shade700,
    };
    final label = switch (post.kind) {
      PostKind.helpOffer => 'Offer',
      PostKind.helpRequest => 'Request',
      PostKind.communityEvent => 'Event',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              isThreeLine: true,
              leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.2), child: Text(label[0])),
              title: Text(post.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat.yMMMd().add_jm().format(post.createdAt)} · ${post.tags.take(3).join(', ')}',
                  ),
                  PostAuthorTapRow(
                    authorId: post.authorId,
                    authorName: post.authorName,
                    avatarRadius: 16,
                    textStyle: Theme.of(context).textTheme.bodySmall,
                    enableProfileTap: false,
                  ),
                ],
              ),
              onTap: () => post.kind == PostKind.communityEvent
                  ? context.push('/event/${post.id}')
                  : context.push('/posts/${post.id}'),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: PostSaveButton(contentId: post.id),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context) {
    final host = event.organizerName.trim().isNotEmpty ? event.organizerName.trim() : 'Organizer';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              isThreeLine: true,
              leading: CircleAvatar(
                backgroundColor: Colors.deepOrange.shade100,
                child: Icon(Icons.event, color: Colors.deepOrange.shade800),
              ),
              title: Text(event.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatEventScheduleLine(event)),
                  const SizedBox(height: 6),
                  PostAuthorTapRow(
                    authorId: event.organizerId,
                    authorName: host,
                    prefix: 'Led by ',
                    avatarRadius: 16,
                    textStyle: Theme.of(context).textTheme.bodySmall,
                    enableProfileTap: false,
                  ),
                ],
              ),
              onTap: () => context.push('/event/${event.id}'),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: PostSaveButton(contentId: event.id),
          ),
        ],
      ),
    );
  }
}
