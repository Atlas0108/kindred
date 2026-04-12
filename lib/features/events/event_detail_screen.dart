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
import '../../widgets/message_poster_button.dart';
import '../../widgets/post_author_row.dart';

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Event'),
      ),
      body: StreamBuilder(
        stream: context.read<EventService>().watchEventDocument(eventId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = snap.data;
          if (doc == null || !doc.exists) {
            return const Center(child: Text('Event not found'));
          }
          final event = CommunityEvent.fromFirestoreDoc(doc);
          if (event == null) {
            return const Center(child: Text('Invalid event'));
          }
          return _EventBody(event: event);
        },
      ),
    );
  }
}

class _EventBody extends StatefulWidget {
  const _EventBody({required this.event});

  final CommunityEvent event;

  @override
  State<_EventBody> createState() => _EventBodyState();
}

class _EventBodyState extends State<_EventBody> {
  bool _deleting = false;

  Future<void> _confirmAndDeleteEvent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final eventService = context.read<EventService>();
    final goRouter = GoRouter.of(context);
    setState(() => _deleting = true);
    try {
      await eventService.deleteEvent(widget.event);
      // StreamBuilder rebuilds as soon as the doc is gone, so this State can be
      // disposed before await returns — use router captured above, not context.pop.
      if (goRouter.canPop()) goRouter.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
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
          if (event.organizerId.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: PostAuthorTapRow(
                    authorId: event.organizerId,
                    authorName: event.organizerName.trim().isNotEmpty
                        ? event.organizerName.trim()
                        : 'Organizer',
                    prefix: 'Led by ',
                    avatarRadius: 20,
                    textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                MessagePosterButton(
                  authorId: event.organizerId,
                  authorName:
                      event.organizerName.trim().isNotEmpty ? event.organizerName.trim() : 'Organizer',
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else if (event.organizerName.isNotEmpty) ...[
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
                return Row(
                  children: [
                    Expanded(
                      child: _RsvpSegment(
                        label: 'Going',
                        selected: current == RsvpStatus.going,
                        onPressed: () => eventService.setMyRsvp(event.id, RsvpStatus.going),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RsvpSegment(
                        label: 'Maybe',
                        selected: current == RsvpStatus.maybe,
                        onPressed: () => eventService.setMyRsvp(event.id, RsvpStatus.maybe),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RsvpSegment(
                        label: 'Can’t go',
                        selected: current == RsvpStatus.declined,
                        onPressed: () => eventService.setMyRsvp(event.id, RsvpStatus.declined),
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
                    final myUid = user?.uid;
                    final openOthersProfile = myUid != null && r.userId != myUid;
                    return FutureBuilder<String>(
                      future: _displayName(userProfileService, r.userId),
                      builder: (context, nameSnap) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline),
                          title: Text(nameSnap.data ?? r.userId),
                          trailing: openOthersProfile
                              ? Icon(
                                  Icons.chevron_right,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                )
                              : null,
                          onTap: openOthersProfile ? () => context.push('/u/${r.userId}') : null,
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
          if (isOrganizer) ...[
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => context.push('/event/${event.id}/edit'),
              child: const Text('Edit Event'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _deleting ? null : _confirmAndDeleteEvent,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              child: _deleting
                  ? SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  : const Text('Delete Event'),
            ),
          ],
        ],
      ),
    );
  }

  static Future<String> _displayName(UserProfileService svc, String uid) async {
    final p = await svc.fetchProfile(uid);
    return p?.publicDisplayLabel ?? uid;
  }
}

/// Outlined when unselected (Maybe-style); filled primary when selected (Going-style).
class _RsvpSegment extends StatelessWidget {
  const _RsvpSegment({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  static const _radius = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  static const _padding = EdgeInsets.symmetric(vertical: 14, horizontal: 8);

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: _padding,
          shape: _radius,
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: _padding,
        shape: _radius,
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    );
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
