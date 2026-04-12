import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/post_service.dart';

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
  bool _busy = false;
  String? _helperId;

  Future<void> _markKindred() async {
    setState(() => _busy = true);
    try {
      await context.read<PostService>().markFulfilledWithThankYou(
            request: widget.post,
            helperUserId: _helperId,
            createThankYouPost: true,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked Kindred — thank you post added.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final user = FirebaseAuth.instance.currentUser;
    final isAuthor = user?.uid == post.authorId;
    final kindLabel = switch (post.kind) {
      PostKind.helpOffer => 'Offer of help',
      PostKind.helpRequest => 'Request for help',
      PostKind.thankYou => 'Thank you',
    };
    final color = switch (post.kind) {
      PostKind.helpOffer => Colors.green,
      PostKind.helpRequest => Colors.blue,
      PostKind.thankYou => Colors.amber.shade800,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.circle, color: color, size: 14),
              const SizedBox(width: 8),
              Text(kindLabel, style: Theme.of(context).textTheme.labelLarge),
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
          Text(post.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            DateFormat.yMMMd().add_jm().format(post.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (post.body != null && post.body!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(post.body!, style: Theme.of(context).textTheme.bodyLarge),
          ],
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: post.tags.map((t) => Chip(label: Text(t))).toList(),
            ),
          ],
          if (isAuthor &&
              post.kind == PostKind.helpRequest &&
              post.status == PostStatus.open) ...[
            const SizedBox(height: 24),
            Text(
              'Optional: helper user ID (stored on the request for future karma).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Helper user ID',
                hintText: 'Paste Firebase Auth UID',
              ),
              onChanged: (v) => _helperId = v.trim().isEmpty ? null : v.trim(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _markKindred,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kindred’d'),
            ),
          ],
        ],
      ),
    );
  }
}
