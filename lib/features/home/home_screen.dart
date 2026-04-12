import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/kindred_trace.dart';
import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/event_service.dart';
import '../../core/services/post_service.dart';

/// Home: community events and help-desk posts (newest first, interleaved by `createdAt`).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _pageBackground = Color(0xFFF9F7F2);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: StreamBuilder<List<CommunityEvent>>(
          stream: context.read<EventService>().homeEventsFeed(),
          builder: (context, eventSnap) {
            return StreamBuilder<List<KindredPost>>(
              stream: context.read<PostService>().homePostsFeed(),
              builder: (context, postSnap) {
                final eventWaiting =
                    !eventSnap.hasData && eventSnap.connectionState == ConnectionState.waiting;
                final postWaiting =
                    !postSnap.hasData && postSnap.connectionState == ConnectionState.waiting;
                final loading = eventWaiting || postWaiting;

                if (eventSnap.hasError || postSnap.hasError) {
                  kindredTrace('HomeScreen feed error',
                      '${eventSnap.error ?? ''} ${postSnap.error ?? ''}'.trim());
                  return ColoredBox(
                    color: _pageBackground,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        _KindredEventsHero(
                          onPostEvent: () => context.push('/post/new/event'),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Could not load the feed.\n'
                          '${eventSnap.error ?? postSnap.error}',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (loading) {
                  return ColoredBox(
                    color: _pageBackground,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        _KindredEventsHero(
                          onPostEvent: () => context.push('/post/new/event'),
                        ),
                        const SizedBox(height: 40),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ),
                  );
                }

                final events = eventSnap.data ?? [];
                final posts = postSnap.data ?? [];
                final rows = _mergeFeedRows(context, events, posts);

                if (rows.isEmpty) {
                  return ColoredBox(
                    color: _pageBackground,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        _KindredEventsHero(
                          onPostEvent: () => context.push('/post/new/event'),
                        ),
                        const SizedBox(height: 48),
                        Icon(Icons.forum_outlined, size: 56, color: scheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          'Nothing here yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Post an event above, or add a help offer or request from the Post tab.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return ColoredBox(
                  color: _pageBackground,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      _KindredEventsHero(
                        onPostEvent: () => context.push('/post/new/event'),
                      ),
                      const SizedBox(height: 28),
                      for (int i = 0; i < rows.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        rows[i],
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

List<Widget> _mergeFeedRows(
  BuildContext context,
  List<CommunityEvent> events,
  List<KindredPost> posts,
) {
  final entries = <({DateTime at, Widget child})>[];
  for (var i = 0; i < events.length; i++) {
    entries.add((
      at: events[i].createdAt,
      child: _EventFeedCard(event: events[i], listIndex: i),
    ));
  }
  for (var i = 0; i < posts.length; i++) {
    entries.add((
      at: posts[i].createdAt,
      child: _PostFeedCard(post: posts[i], listIndex: i),
    ));
  }
  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries.map((e) => e.child).toList();
}

class _KindredEventsHero extends StatelessWidget {
  const _KindredEventsHero({required this.onPostEvent});

  final VoidCallback onPostEvent;

  static const _forest = Color(0xFF4A6354);
  static const _descriptionColor = Color(0xFF4A4F54);

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.playfairDisplay(
      fontSize: 40,
      fontWeight: FontWeight.w400,
      color: const Color(0xFF141414),
      height: 1.08,
    );
    final eventsStyle = GoogleFonts.playfairDisplay(
      fontSize: 40,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.italic,
      color: _forest,
      height: 1.08,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kindred', style: titleStyle),
        Text('Events', style: eventsStyle),
        const SizedBox(height: 16),
        Text(
          'Gatherings designed to nourish the soul, tend the earth, and strengthen our collective roots.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _descriptionColor,
                height: 1.55,
                fontSize: 16,
              ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _forest,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            onPressed: onPostEvent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: _forest, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Post an Event',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EventFeedCard extends StatelessWidget {
  const _EventFeedCard({
    required this.event,
    required this.listIndex,
  });

  final CommunityEvent event;
  final int listIndex;

  static const _categoryColor = Color(0xFF6B7B8C);
  static const _arrowColor = Color(0xFF8E9499);
  static const _bodyColor = Color(0xFF5C6268);

  static const _badgeBackgrounds = [
    Color(0xFFDFF2E8),
    Color(0xFFF2EBDD),
    Color(0xFFE3EDFA),
    Color(0xFFFFE8E0),
  ];

  Color _badgeColor() {
    final h = event.id.hashCode ^ listIndex * 17;
    return _badgeBackgrounds[h.abs() % _badgeBackgrounds.length];
  }

  String _categoryLabel() {
    if (event.tags.isEmpty) return 'EVENT';
    final t = event.tags.first.trim();
    if (t.isEmpty) return 'EVENT';
    final upper = t.toUpperCase();
    return upper.length > 22 ? '${upper.substring(0, 22)}…' : upper;
  }

  String _descriptionPreview() {
    final d = event.description.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (d.isNotEmpty) return d;
    final loc = event.locationDescription.trim();
    if (loc.isNotEmpty) return loc;
    return 'Tap for details and schedule.';
  }

  @override
  Widget build(BuildContext context) {
    final start = event.startsAt.toLocal();
    final month = DateFormat('MMM').format(start).toUpperCase();
    final day = DateFormat('d').format(start);

    return _EditorialCard(
      onTap: () => context.push('/event/${event.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DateBadge(month: month, day: day, backgroundColor: _badgeColor()),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(
                  Icons.arrow_forward,
                  size: 22,
                  color: _arrowColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _categoryLabel(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _categoryColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            event.title,
            style: GoogleFonts.lora(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: const Color(0xFF141414),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _descriptionPreview(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _bodyColor,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _PostFeedCard extends StatelessWidget {
  const _PostFeedCard({
    required this.post,
    required this.listIndex,
  });

  final KindredPost post;
  final int listIndex;

  static const _categoryColor = Color(0xFF6B7B8C);
  static const _arrowColor = Color(0xFF8E9499);
  static const _bodyColor = Color(0xFF5C6268);

  static const _badgeBackgrounds = [
    Color(0xFFE8F4E0),
    Color(0xFFE5EEF8),
    Color(0xFFFFF3E0),
    Color(0xFFF3E8FF),
  ];

  Color _badgeColor() {
    final h = post.id.hashCode ^ listIndex * 19;
    return _badgeBackgrounds[h.abs() % _badgeBackgrounds.length];
  }

  String _categoryLabel() {
    return switch (post.kind) {
      PostKind.helpOffer => 'OFFERING HELP',
      PostKind.helpRequest => 'REQUEST',
      PostKind.thankYou => 'THANK YOU',
    };
  }

  String _descriptionPreview() {
    final b = post.body?.trim();
    if (b != null && b.isNotEmpty) {
      return b.replaceAll(RegExp(r'\s+'), ' ');
    }
    if (post.tags.isNotEmpty) {
      return post.tags.take(4).join(' · ');
    }
    return 'Tap to read more.';
  }

  @override
  Widget build(BuildContext context) {
    final created = post.createdAt.toLocal();
    final month = DateFormat('MMM').format(created).toUpperCase();
    final day = DateFormat('d').format(created);

    return _EditorialCard(
      onTap: () => context.push('/posts/${post.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DateBadge(month: month, day: day, backgroundColor: _badgeColor()),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(
                  Icons.arrow_forward,
                  size: 22,
                  color: _arrowColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _categoryLabel(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _categoryColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  fontSize: 11,
                ),
          ),
          if (post.status == PostStatus.fulfilled) ...[
            const SizedBox(height: 6),
            Text(
              'FULFILLED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _categoryColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    fontSize: 10,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            post.title,
            style: GoogleFonts.lora(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: const Color(0xFF141414),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _descriptionPreview(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _bodyColor,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({
    required this.month,
    required this.day,
    required this.backgroundColor,
  });

  final String month;
  final String day;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Text(
              month,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              day,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorialCard extends StatelessWidget {
  const _EditorialCard({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}
