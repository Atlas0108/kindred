import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/event_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/utils/merge_community_events.dart';
import '../../core/constants/default_geo.dart';

class EventsListTab extends StatefulWidget {
  const EventsListTab({super.key});

  @override
  State<EventsListTab> createState() => _EventsListTabState();
}

class _EventsListTabState extends State<EventsListTab> {
  List<CommunityEvent> _legacyEvents = [];
  List<KindredPost> _postsInRadius = [];
  StreamSubscription<List<CommunityEvent>>? _eventSub;
  StreamSubscription<List<KindredPost>>? _postSub;
  String? _key;

  @override
  void dispose() {
    _eventSub?.cancel();
    _postSub?.cancel();
    super.dispose();
  }

  void _attach(GeoPoint center, int radiusMiles) {
    final k =
        '${center.latitude}_${center.longitude}_$radiusMiles';
    if (k == _key) return;
    _key = k;
    _eventSub?.cancel();
    _postSub?.cancel();
    final radius = radiusMiles.toDouble();
    final eventSvc = context.read<EventService>();
    final postSvc = context.read<PostService>();
    _eventSub = eventSvc.eventsInRadius(center: center, radiusMiles: radius).listen((e) {
      if (!mounted) return;
      setState(() => _legacyEvents = e);
    });
    _postSub = postSvc.postsInRadius(center: center, radiusMiles: radius).listen((p) {
      if (!mounted) return;
      setState(() => _postsInRadius = p);
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
        _attach(center, radiusMiles);

        final events = mergeLegacyAndPostEventRows(_legacyEvents, _postsInRadius);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Events'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => context.push('/event/new'),
                tooltip: 'New event',
              ),
            ],
          ),
          body: events.isEmpty
              ? Center(
                  child: Text(
                    'No upcoming events in your radius.\nCreate one with +',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  itemBuilder: (context, i) {
                    final e = events[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepOrange.shade100,
                          child: Icon(Icons.event, color: Colors.deepOrange.shade800),
                        ),
                        title: Text(e.title),
                        subtitle: Text(DateFormat.yMMMd().add_jm().format(e.startsAt)),
                        onTap: () => context.push('/event/${e.id}'),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
