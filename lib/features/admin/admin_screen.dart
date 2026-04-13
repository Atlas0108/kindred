import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/auth/public_commons_admin.dart';
import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/post_service.dart';
import '../../core/utils/event_formatting.dart';

/// In-app workspace for `*@publiccommons.app` team accounts.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: const Text('Admin'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Moderation'),
            Tab(text: 'Feed Import'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AdminModerationTab(),
          _AdminFeedImportTab(),
          _AdminSettingsTab(),
        ],
      ),
    );
  }
}

class _AdminModerationTab extends StatelessWidget {
  const _AdminModerationTab();

  static String _kindLabel(PostKind k) {
    return switch (k) {
      PostKind.helpOffer => 'Offering help',
      PostKind.helpRequest => 'Requesting help',
      PostKind.communityEvent => 'Event',
    };
  }

  @override
  Widget build(BuildContext context) {
    final postsSvc = context.read<PostService>();
    final theme = Theme.of(context);
    final fmt = DateFormat.yMMMd().add_jm();

    return StreamBuilder<List<KindredPost>>(
      stream: postsSvc.moderationPostsFeed(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load posts.\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final posts = snap.data ?? [];
        if (posts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No posts yet.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '${posts.length} most recent posts (newest first)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = posts[i];
                  if (p.kind == PostKind.communityEvent) {
                    final e = CommunityEvent.fromKindredPost(p);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(
                          Icons.event_outlined,
                          color: Colors.deepOrange.shade700,
                        ),
                        title: Text(
                          p.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${p.authorName} · Event · ${e != null ? formatEventScheduleLine(e) : fmt.format(p.createdAt.toLocal())}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/admin/review/post/${p.id}'),
                      ),
                    );
                  }
                  final status = p.status == PostStatus.fulfilled ? 'Fulfilled' : 'Open';
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(
                        Icons.article_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${p.authorName} · ${_kindLabel(p.kind)} · $status · ${fmt.format(p.createdAt.toLocal())}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/admin/review/post/${p.id}'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AdminFeedImportTab extends StatelessWidget {
  const _AdminFeedImportTab();

  @override
  Widget build(BuildContext context) {
    return _AdminPlaceholderTab(
      title: 'Feed import',
      body:
          'Bring in external listings or bulk content for the home feed. Add importers '
          'and validation flows here.',
    );
  }
}

class _AdminSettingsTab extends StatelessWidget {
  const _AdminSettingsTab();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          'Settings',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Signed in as $email',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team access',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'The Admin area is only visible when you sign in with an address ending in '
                  '$kPublicCommonsAdminEmailDomain.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _AdminPlaceholderTab extends StatelessWidget {
  const _AdminPlaceholderTab({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          body,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
