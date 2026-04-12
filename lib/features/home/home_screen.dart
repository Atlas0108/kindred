import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/kindred_trace.dart';
import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/event_service.dart';
import '../../core/services/post_service.dart';
import '../../widgets/post_author_row.dart';
import '../../widgets/post_save_button.dart';

Widget _feedCardWithSave(String contentId, Widget editorialCard) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      editorialCard,
      Positioned(
        right: 6,
        bottom: 6,
        child: PostSaveButton(contentId: contentId),
      ),
    ],
  );
}

/// Home: community events and help-desk posts (newest first), with category tabs.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const _pageBackground = Color(0xFFF9F7F2);

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

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
                final postWaiting =
                    !postSnap.hasData && postSnap.connectionState == ConnectionState.waiting;

                if (eventSnap.hasError || postSnap.hasError) {
                  kindredTrace(
                    'HomeScreen feed error',
                    '${eventSnap.error ?? ''} ${postSnap.error ?? ''}'.trim(),
                  );
                  return ColoredBox(
                    color: _pageBackground,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        _KindredEventsHero(onMakePost: () => context.go('/post')),
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

                final events = eventSnap.data ?? [];
                final posts = postSnap.data ?? [];
                final entries = _buildFeedEntries(context, events, posts, postWaiting: postWaiting);
                final filtered = _filterEntries(entries, _tabController.index);
                final rows = filtered.map((e) => e.card).toList();

                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _KindredEventsHero(onMakePost: () => context.go('/post')),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedTabBarDelegate(
                        scheme: scheme,
                        backgroundColor: _pageBackground,
                        tabController: _tabController,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyFilterState(tabIndex: _tabController.index, scheme: scheme),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => Padding(
                              padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
                              child: rows[i],
                            ),
                            childCount: rows.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

enum _FeedEntryKind { event, offer, request, skeleton }

class _FeedEntry {
  _FeedEntry({required this.at, required this.card, required this.kind});

  final DateTime at;
  final Widget card;
  final _FeedEntryKind kind;
}

List<_FeedEntry> _buildFeedEntries(
  BuildContext context,
  List<CommunityEvent> events,
  List<KindredPost> posts, {
  required bool postWaiting,
}) {
  final entries = <_FeedEntry>[];
  for (var i = 0; i < events.length; i++) {
    entries.add(
      _FeedEntry(
        at: events[i].createdAt,
        card: _EventFeedCard(event: events[i], listIndex: i),
        kind: _FeedEntryKind.event,
      ),
    );
  }
  for (var i = 0; i < posts.length; i++) {
    final p = posts[i];
    if (p.kind == PostKind.communityEvent) {
      final e = CommunityEvent.fromKindredPost(p);
      if (e != null) {
        entries.add(
          _FeedEntry(
            at: p.createdAt,
            card: _EventFeedCard(event: e, listIndex: i),
            kind: _FeedEntryKind.event,
          ),
        );
      }
      continue;
    }
    final kind = p.kind == PostKind.helpOffer ? _FeedEntryKind.offer : _FeedEntryKind.request;
    entries.add(
      _FeedEntry(
        at: p.createdAt,
        card: _PostFeedCard(post: p, listIndex: i),
        kind: kind,
      ),
    );
  }
  if (postWaiting) {
    final anchor = DateTime.now();
    for (var i = 0; i < 2; i++) {
      entries.add(
        _FeedEntry(
          at: anchor.add(Duration(microseconds: i)),
          card: const _PostFeedCardSkeleton(),
          kind: _FeedEntryKind.skeleton,
        ),
      );
    }
  }
  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries;
}

/// 0 All, 1 Events, 2 Offers, 3 Requests
List<_FeedEntry> _filterEntries(List<_FeedEntry> entries, int tabIndex) {
  return switch (tabIndex) {
    0 => entries,
    1 => entries.where((e) => e.kind == _FeedEntryKind.event).toList(),
    2 => entries.where((e) => e.kind == _FeedEntryKind.offer).toList(),
    3 => entries.where((e) => e.kind == _FeedEntryKind.request).toList(),
    _ => entries,
  };
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.tabIndex, required this.scheme});

  final int tabIndex;
  final ColorScheme scheme;

  String get _title => switch (tabIndex) {
    1 => 'No events yet',
    2 => 'No offers yet',
    3 => 'No requests yet',
    _ => 'Nothing here yet',
  };

  String get _subtitle => switch (tabIndex) {
    1 => 'Create an event from the Post tab.',
    2 => 'Share what you can do from the Post tab.',
    3 => 'Ask for a hand from the Post tab.',
    _ => 'Tap Make a post above, or use the Post tab.',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              _title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedTabBarDelegate({
    required this.scheme,
    required this.backgroundColor,
    required this.tabController,
  });

  final ColorScheme scheme;
  final Color backgroundColor;
  final TabController tabController;

  static const double _tabBarHeight = 48;

  @override
  double get minExtent => _tabBarHeight;

  @override
  double get maxExtent => _tabBarHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TabBar(
          controller: tabController,
          isScrollable: false,
          tabAlignment: TabAlignment.fill,
          labelColor: const Color(0xFF4A6354),
          unselectedLabelColor: scheme.onSurfaceVariant,
          indicatorColor: const Color(0xFF4A6354),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Events'),
            Tab(text: 'Offers'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedTabBarDelegate oldDelegate) {
    return scheme != oldDelegate.scheme ||
        backgroundColor != oldDelegate.backgroundColor ||
        tabController != oldDelegate.tabController;
  }
}

class _KindredEventsHero extends StatelessWidget {
  const _KindredEventsHero({required this.onMakePost});

  final VoidCallback onMakePost;

  static const _forest = Color(0xFF4A6354);
  static const _descriptionColor = Color(0xFF4A4F54);

  @override
  Widget build(BuildContext context) {
    final titleStyle = GoogleFonts.playfairDisplay(
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
        const SizedBox(height: 16),
        Text(
          'A platform designed to nourish the soul, tend to our communities, and strengthen our collective roots.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: _descriptionColor, height: 1.55, fontSize: 16),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _forest,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: onMakePost,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.add, color: _forest, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Make a post',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
  const _EventFeedCard({required this.event, required this.listIndex});

  final CommunityEvent event;
  final int listIndex;

  static const _categoryColor = Color(0xFF6B7B8C);
  static const _forestCategory = Color(0xFF4A6354);
  static const _arrowColor = Color(0xFF8E9499);
  static const _bodyColor = Color(0xFF5C6268);
  static const _metaGrey = Color(0xFF5C6268);
  static const _authorGrey = Color(0xFF6B7280);

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
    return upper.length > 28 ? '${upper.substring(0, 28)}…' : upper;
  }

  String _descriptionPreview() {
    final d = event.description.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (d.isNotEmpty) return d;
    final loc = event.locationDescription.trim();
    if (loc.isNotEmpty) return loc;
    return 'Tap for details and schedule.';
  }

  bool get _hasImage => event.imageUrl != null && event.imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_hasImage) {
      return _buildImageHeroCard(context);
    }
    final start = event.startsAt.toLocal();
    final month = DateFormat('MMM').format(start).toUpperCase();
    final day = DateFormat('d').format(start);

    return _feedCardWithSave(
      event.id,
      _EditorialCard(
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
                  child: Icon(Icons.arrow_forward, size: 22, color: _arrowColor),
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _bodyColor, height: 1.45),
            ),
            const SizedBox(height: 20),
            PostAuthorTapRow(
              authorId: event.organizerId,
              authorName: event.organizerName.trim().isNotEmpty
                  ? event.organizerName.trim()
                  : 'Organizer',
              prefix: 'Led by ',
              enableProfileTap: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageHeroCard(BuildContext context) {
    final url = event.imageUrl!.trim();
    final timeText = DateFormat.jm().format(event.startsAt.toLocal());
    final host = event.organizerName.trim().isNotEmpty ? event.organizerName.trim() : 'Organizer';

    return _feedCardWithSave(
      event.id,
      _EditorialCard(
        onTap: () => context.push('/event/${event.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return ColoredBox(
                      color: Colors.grey.shade200,
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: Colors.grey.shade300,
                    child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade600, size: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _categoryLabel(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _forestCategory,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      fontSize: 11,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 16, color: _metaGrey.withValues(alpha: 0.9)),
                    const SizedBox(width: 4),
                    Text(
                      timeText,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _metaGrey,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              event.title,
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                fontWeight: FontWeight.w500,
                height: 1.2,
                color: const Color(0xFF141414),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _descriptionPreview(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _bodyColor, height: 1.5, fontSize: 15),
            ),
            const SizedBox(height: 20),
            PostAuthorTapRow(
              authorId: event.organizerId,
              authorName: host,
              prefix: 'Led by ',
              enableProfileTap: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _PostFeedCardSkeleton extends StatelessWidget {
  const _PostFeedCardSkeleton();

  static const _bone = Color(0xFFE4E2DD);

  @override
  Widget build(BuildContext context) {
    Widget boneLine(double height, {double? width}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(color: _bone, borderRadius: BorderRadius.circular(6)),
      );
    }

    return IgnorePointer(
      child: _EditorialCard(
        onTap: () {},
        child: Shimmer.fromColors(
          baseColor: _bone,
          highlightColor: Colors.white,
          period: const Duration(milliseconds: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 52,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _bone,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _bone,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              boneLine(10, width: 96),
              const SizedBox(height: 14),
              boneLine(22),
              const SizedBox(height: 10),
              boneLine(14),
              const SizedBox(height: 8),
              boneLine(14),
              const SizedBox(height: 8),
              boneLine(14, width: 200),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: _bone, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: boneLine(14)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostFeedCard extends StatelessWidget {
  const _PostFeedCard({required this.post, required this.listIndex});

  final KindredPost post;
  final int listIndex;

  static const _categoryColor = Color(0xFF6B7B8C);
  static const _forestCategory = Color(0xFF4A6354);
  static const _arrowColor = Color(0xFF8E9499);
  static const _bodyColor = Color(0xFF5C6268);
  static const _metaGrey = Color(0xFF5C6268);

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
      PostKind.communityEvent => 'EVENT',
    };
  }

  /// Primary line under the hero image: first tag (caps) or kind label.
  String _heroCategoryLine() {
    if (post.tags.isNotEmpty) {
      final t = post.tags.first.trim();
      if (t.isNotEmpty) {
        final u = t.toUpperCase();
        return u.length > 28 ? '${u.substring(0, 28)}…' : u;
      }
    }
    return _categoryLabel();
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

  bool get _hasImage => post.imageUrl != null && post.imageUrl!.trim().isNotEmpty;

  void _openDetail(BuildContext context) {
    if (post.kind == PostKind.communityEvent) {
      context.push('/event/${post.id}');
    } else {
      context.push('/posts/${post.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasImage) {
      return _buildImageHeroCard(context);
    }
    final created = post.createdAt.toLocal();
    final month = DateFormat('MMM').format(created).toUpperCase();
    final day = DateFormat('d').format(created);

    return _feedCardWithSave(
      post.id,
      _EditorialCard(
        onTap: () => _openDetail(context),
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
                  child: Icon(Icons.arrow_forward, size: 22, color: _arrowColor),
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _bodyColor, height: 1.45),
            ),
            const SizedBox(height: 20),
            PostAuthorTapRow(
              authorId: post.authorId,
              authorName: post.authorName,
              enableProfileTap: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageHeroCard(BuildContext context) {
    final url = post.imageUrl!.trim();
    final timeText = DateFormat.jm().format(post.createdAt.toLocal());

    return _feedCardWithSave(
      post.id,
      _EditorialCard(
        onTap: () => _openDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return ColoredBox(
                      color: Colors.grey.shade200,
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: Colors.grey.shade300,
                    child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade600, size: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _heroCategoryLine(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _forestCategory,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          fontSize: 11,
                        ),
                      ),
                      if (post.status == PostStatus.fulfilled) ...[
                        const SizedBox(height: 4),
                        Text(
                          'FULFILLED',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _forestCategory,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 16, color: _metaGrey.withValues(alpha: 0.9)),
                    const SizedBox(width: 4),
                    Text(
                      timeText,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _metaGrey,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.title,
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                fontWeight: FontWeight.w500,
                height: 1.2,
                color: const Color(0xFF141414),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _descriptionPreview(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _bodyColor, height: 1.5, fontSize: 15),
            ),
            const SizedBox(height: 20),
            PostAuthorTapRow(
              authorId: post.authorId,
              authorName: post.authorName,
              enableProfileTap: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.month, required this.day, required this.backgroundColor});

  final String month;
  final String day;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(14)),
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
            Text(day, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
          ],
        ),
      ),
    );
  }
}

class _EditorialCard extends StatelessWidget {
  const _EditorialCard({required this.onTap, required this.child});

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
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );
  }
}
