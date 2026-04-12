import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/community_event.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/event_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/constants/default_geo.dart';

class EventsListTab extends StatefulWidget {
  const EventsListTab({super.key});

  @override
  State<EventsListTab> createState() => _EventsListTabState();
}

class _EventsListTabState extends State<EventsListTab> {
  List<CommunityEvent> _events = [];
  StreamSubscription<List<CommunityEvent>>? _sub;
  String? _key;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _attach(GeoPoint center, int radiusMiles) {
    final k =
        '${center.latitude}_${center.longitude}_$radiusMiles';
    if (k == _key) return;
    _key = k;
    _sub?.cancel();
    _sub = context.read<EventService>().eventsInRadius(
          center: center,
          radiusMiles: radiusMiles.toDouble(),
        ).listen((e) {
      if (mounted) setState(() => _events = e);
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
          body: _events.isEmpty
              ? Center(
                  child: Text(
                    'No upcoming events in your radius.\nCreate one with +',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _events.length,
                  itemBuilder: (context, i) {
                    final e = _events[i];
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
