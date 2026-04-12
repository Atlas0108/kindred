import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/community_event.dart';
import '../../core/models/rsvp.dart';
import '../../core/services/event_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/utils/event_formatting.dart';
import '../../core/utils/link_utils.dart';

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('events').doc(eventId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Event'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Event not found'));
          }
          final event = CommunityEvent.fromDoc(snap.data!);
          if (event == null) {
            return const Center(child: Text('Invalid event'));
          }
          return _EventBody(event: event);
        },
      ),
    );
  }
}

class _EventBody extends StatelessWidget {
  const _EventBody({required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isOrganizer = user?.uid == event.organizerId;
    final eventService = context.read<EventService>();
    final userProfileService = context.read<UserProfileService>();

    final hasImage = event.imageUrl != null && event.imageUrl!.trim().isNotEmpty;
    final imageUrl = hasImage ? event.imageUrl!.trim() : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return ColoredBox(
                      color: Colors.grey.shade200,
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  },
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: Colors.grey.shade300,
                    child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade600, size: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            event.title,
            style: hasImage
                ? GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: const Color(0xFF141414),
                  )
                : Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          if (event.organizerName.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.person_outline, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(event.organizerName)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(formatEventScheduleLine(event)),
              ),
            ],
          ),
          if (event.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: event.tags
                  .map(
                    (t) => Chip(
                      label: Text(t),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (event.locationDescription.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: _LocationBlock(text: event.locationDescription)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(event.description, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          Text('RSVP', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (user != null)
            StreamBuilder<EventRsvp?>(
              stream: eventService.myRsvpStream(event.id),
              builder: (context, snap) {
                final current = snap.data?.status;
                return Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => eventService.setMyRsvp(event.id, RsvpStatus.going),
                      child: const Text('Going'),
                    ),
                    OutlinedButton(
                      onPressed: () => eventService.setMyRsvp(event.id, RsvpStatus.maybe),
                      child: const Text('Maybe'),
                    ),
                    TextButton(
                      onPressed: () => eventService.setMyRsvp(event.id, RsvpStatus.declined),
                      child: const Text('Can’t go'),
                    ),
                    if (current != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Center(
                          child: Text(
                            'You: ${current.name}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                  ],
                );
              },
            )
          else
            const Text('Sign in to RSVP'),
          if (isOrganizer) ...[
            const SizedBox(height: 32),
            Text('Attendees', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            StreamBuilder<List<EventRsvp>>(
              stream: eventService.rsvpsStream(event.id),
              builder: (context, snap) {
                final list = snap.data ?? [];
                final going = list.where((r) => r.status == RsvpStatus.going).toList();
                if (going.isEmpty) {
                  return const Text('No one marked going yet.');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: going.map((r) {
                    return FutureBuilder<String>(
                      future: _displayName(userProfileService, r.userId),
                      builder: (context, nameSnap) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline),
                          title: Text(nameSnap.data ?? r.userId),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  static Future<String> _displayName(UserProfileService svc, String uid) async {
    final p = await svc.fetchProfile(uid);
    return p?.displayName ?? uid;
  }
}

class _LocationBlock extends StatelessWidget {
  const _LocationBlock({required this.text});

  final String text;

  Future<void> _open() async {
    final uri = Uri.parse(text.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (locationTextLooksLikeHttpUrl(text)) {
      return InkWell(
        onTap: _open,
        child: Text(
          text.trim(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary,
          ),
        ),
      );
    }
    return SelectableText(text.trim(), style: theme.textTheme.bodyLarge);
  }
}
