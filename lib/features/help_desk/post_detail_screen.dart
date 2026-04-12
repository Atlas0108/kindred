import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/post_service.dart';
import '../../widgets/message_poster_button.dart';
import '../../widgets/post_author_row.dart';
import '../../widgets/post_kind_icon_badge.dart';

class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('posts').doc(postId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Post'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Post not found'));
          }
          final post = KindredPost.fromDoc(snap.data!);
          if (post == null) {
            return const Center(child: Text('Invalid post'));
          }
          if (post.kind == PostKind.communityEvent) {
            return _RedirectCommunityEventToDetail(postId: post.id);
          }
          return _PostBody(post: post);
        },
      ),
    );
  }
}

class _PostBody extends StatefulWidget {
  const _PostBody({required this.post});

  final KindredPost post;

  @override
  State<_PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends State<_PostBody> {
  bool _deleting = false;

  Future<void> _confirmAndDeletePost() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
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
    setState(() => _deleting = true);
    try {
      await context.read<PostService>().deletePost(widget.post);
      if (mounted) context.pop();
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
    final post = widget.post;
    final user = FirebaseAuth.instance.currentUser;
    final isAuthor = user?.uid == post.authorId;
    final hasImage = post.imageUrl != null && post.imageUrl!.trim().isNotEmpty;
    final imageUrl = hasImage ? post.imageUrl!.trim() : '';

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PostKindIconBadge(kind: post.kind),
              const SizedBox(width: 12),
              Text(
                postKindListHeadline(post.kind),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF6B7B8C),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                      fontSize: 11,
                    ),
              ),
              if (post.status == PostStatus.fulfilled) ...[
                const SizedBox(width: 12),
                Chip(
                  label: const Text('Fulfilled'),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            post.title,
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
          Text(
            DateFormat.yMMMd().add_jm().format(post.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: PostAuthorTapRow(
                  authorId: post.authorId,
                  authorName: post.authorName,
                  avatarRadius: 20,
                  textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                  showVerifiedBadge: true,
                  verifiedIconSize: 16,
                ),
              ),
              const SizedBox(width: 10),
              MessagePosterButton(authorId: post.authorId, authorName: post.authorName),
            ],
          ),
          if (post.body != null && post.body!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(post.body!, style: Theme.of(context).textTheme.bodyLarge),
          ],
          if (isAuthor) ...[
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => context.push('/posts/${post.id}/edit'),
              child: const Text('Edit Post'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _deleting ? null : _confirmAndDeletePost,
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
                  : const Text('Delete Post'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RedirectCommunityEventToDetail extends StatefulWidget {
  const _RedirectCommunityEventToDetail({required this.postId});

  final String postId;

  @override
  State<_RedirectCommunityEventToDetail> createState() => _RedirectCommunityEventToDetailState();
}

class _RedirectCommunityEventToDetailState extends State<_RedirectCommunityEventToDetail> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/event/${widget.postId}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
