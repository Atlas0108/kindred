import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/default_geo.dart';
import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/event_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/utils/event_formatting.dart';
import '../../widgets/post_author_row.dart';

/// Legacy "map" tab: list of posts and events near the profile (or default) point.
class DiscoveryMapTab extends StatefulWidget {
  const DiscoveryMapTab({super.key});

  @override
  State<DiscoveryMapTab> createState() => _DiscoveryMapTabState();
}

class _DiscoveryMapTabState extends State<DiscoveryMapTab> {
  List<KindredPost> _posts = [];
  List<CommunityEvent> _events = [];
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
    final key = '${center.latitude}_${center.longitude}_$radiusMiles';
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
      if (mounted) setState(() => _events = list);
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
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snap.data;
        final center = profile?.homeGeoPoint ?? kDefaultGeoPoint;
        final radiusMiles = profile?.discoveryRadiusMiles ?? 25;
        _attachDiscoveryIfNeeded(center, radiusMiles);

        final rows = <_NearbyRow>[
          ..._posts.map(_NearbyRow.post),
          ..._events.map(_NearbyRow.event),
        ]..sort((a, b) => b.sortTime.compareTo(a.sortTime));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Nearby'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    '$radiusMiles mi',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
          body: rows.isEmpty
              ? const Center(child: Text('Nothing in range yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row.post != null) return _PostRowTile(post: row.post!);
                    return _EventRowTile(event: row.event!);
                  },
                ),
        );
      },
    );
  }
}

class _NearbyRow {
  _NearbyRow.post(KindredPost p) : post = p, event = null, sortTime = p.createdAt;
  _NearbyRow.event(CommunityEvent e) : post = null, event = e, sortTime = e.startsAt;

  final KindredPost? post;
  final CommunityEvent? event;
  final DateTime sortTime;
}

class _PostRowTile extends StatelessWidget {
  const _PostRowTile({required this.post});

  final KindredPost post;

  @override
  Widget build(BuildContext context) {
    final color = switch (post.kind) {
      PostKind.helpOffer => Colors.green.shade700,
      PostKind.helpRequest => Colors.blue.shade700,
      PostKind.thankYou => Colors.amber.shade800,
    };
    final label = switch (post.kind) {
      PostKind.helpOffer => 'Offer',
      PostKind.helpRequest => 'Request',
      PostKind.thankYou => 'Thank you',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Text(label[0]),
        ),
        title: Text(post.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMMMd().add_jm().format(post.createdAt)),
            PostAuthorTapRow(
              authorId: post.authorId,
              authorName: post.authorName,
              avatarRadius: 16,
              textStyle: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        onTap: () => context.push('/posts/${post.id}'),
      ),
    );
  }
}

class _EventRowTile extends StatelessWidget {
  const _EventRowTile({required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.deepOrange.shade100,
          child: Icon(Icons.event, color: Colors.deepOrange.shade800),
        ),
        title: Text(event.title),
        subtitle: Text(formatEventScheduleLine(event)),
        onTap: () => context.push('/event/${event.id}'),
      ),
    );
  }
}
