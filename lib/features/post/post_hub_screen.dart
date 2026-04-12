import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/event_service.dart';
import '../../core/services/post_service.dart';
import '../../core/utils/event_formatting.dart';

/// Post tab: create new content, or browse your own posts.
class PostHubScreen extends StatefulWidget {
  const PostHubScreen({super.key});

  @override
  State<PostHubScreen> createState() => _PostHubScreenState();
}

class _PostHubScreenState extends State<PostHubScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'New Post'),
            Tab(text: 'My Posts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _NewPostTab(),
          _MyPostsTab(),
        ],
      ),
    );
  }
}

class _NewPostTab extends StatelessWidget {
  const _NewPostTab();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'What would you like to share?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Events go on the calendar; offers and requests are help-desk posts.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            _PostTypeCard(
              icon: Icons.event_available_outlined,
              iconColor: scheme.primary,
              title: 'Event',
              subtitle:
                  'Title, organizer, description, categories, schedule, and location or meeting link.',
              onTap: () => context.push('/post/new/event'),
            ),
            const SizedBox(height: 12),
            _PostTypeCard(
              icon: Icons.handshake_outlined,
              iconColor: Colors.green.shade700,
              title: 'Offering help',
              subtitle: 'Something you can do or lend to neighbors.',
              onTap: () => context.push('/compose?kind=offer'),
            ),
            const SizedBox(height: 12),
            _PostTypeCard(
              icon: Icons.support_agent_outlined,
              iconColor: Colors.blue.shade700,
              title: 'Requesting help',
              subtitle: 'Ask for a hand, tools, or local knowledge.',
              onTap: () => context.push('/compose?kind=request'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyPostsTab extends StatelessWidget {
  const _MyPostsTab();

  static String _kindLabel(PostKind k) {
    return switch (k) {
      PostKind.helpOffer => 'Offering help',
      PostKind.helpRequest => 'Requesting help',
      PostKind.communityEvent => 'Event',
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Sign in to see your posts.'));
    }

    final postSvc = context.read<PostService>();
    final eventSvc = context.read<EventService>();

    return StreamBuilder<List<KindredPost>>(
      stream: postSvc.myPostsFeed(),
      builder: (context, postSnap) {
        return StreamBuilder<List<CommunityEvent>>(
          stream: eventSvc.myOrganizedEventsFeed(),
          builder: (context, eventSnap) {
            final postsWaiting =
                postSnap.connectionState == ConnectionState.waiting && !postSnap.hasData;
            final eventsWaiting =
                eventSnap.connectionState == ConnectionState.waiting && !eventSnap.hasData;
            if (postsWaiting && eventsWaiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (postSnap.hasError || eventSnap.hasError) {
              final err = postSnap.error ?? eventSnap.error;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load your content.\n$err',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final posts = postSnap.data ?? [];
            final events = eventSnap.data ?? [];
            final fmt = DateFormat.yMMMd().add_jm();

            final rows = <({DateTime sortAt, Widget tile})>[];
            for (final p in posts) {
              if (p.kind == PostKind.communityEvent) {
                final e = CommunityEvent.fromKindredPost(p);
                if (e != null) {
                  rows.add((
                    sortAt: p.createdAt,
                    tile: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Icon(Icons.event_outlined, color: Colors.deepOrange.shade700),
                        title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          'Event · ${formatEventScheduleLine(e)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/event/${p.id}'),
                      ),
                    ),
                  ));
                }
                continue;
              }
              rows.add((
                sortAt: p.createdAt,
                tile: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(Icons.article_outlined, color: Theme.of(context).colorScheme.primary),
                    title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${_kindLabel(p.kind)} · ${fmt.format(p.createdAt.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/posts/${p.id}'),
                  ),
                ),
              ));
            }
            for (final e in events) {
              rows.add((
                sortAt: e.createdAt,
                tile: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(Icons.event_outlined, color: Colors.deepOrange.shade700),
                    title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      'Event · ${formatEventScheduleLine(e)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/event/${e.id}'),
                  ),
                ),
              ));
            }
            rows.sort((a, b) => b.sortAt.compareTo(a.sortAt));

            if (rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.post_add_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'Nothing here yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the New Post tab to create an event, offer, or request.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => rows[i].tile,
            );
          },
        );
      },
    );
  }
}

class _PostTypeCard extends StatelessWidget {
  const _PostTypeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
