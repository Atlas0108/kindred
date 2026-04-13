import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/kindred_scaffold_messenger.dart';
import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/utils/event_formatting.dart';
import '../../widgets/post_kind_icon_badge.dart';

/// Desktop-oriented review surface for a single post (help desk or event).
class AdminPostReviewScreen extends StatelessWidget {
  const AdminPostReviewScreen({super.key, required this.postId});

  final String postId;

  static const _maxContentWidth = 1080.0;
  static const _imageColumnWidth = 300.0;
  static const _imageHeight = 220.0;
  static const _twoColBreakpoint = 800.0;

  String _publicPath(KindredPost post) {
    return post.kind == PostKind.communityEvent ? '/event/$postId' : '/posts/$postId';
  }

  void _snack(String message) {
    kindredScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _snack('Copied $label');
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('posts').doc(postId);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Post review'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/admin'),
          tooltip: 'Back',
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Could not load post.\n${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final doc = snap.data;
          if (doc == null || !doc.exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Post not found.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.canPop() ? context.pop() : context.go('/admin'),
                      child: const Text('Back to admin'),
                    ),
                  ],
                ),
              ),
            );
          }

          final post = KindredPost.fromDoc(doc);
          if (post == null) {
            return const Center(child: Text('Invalid post document.'));
          }

          final theme = Theme.of(context);
          final fmt = DateFormat.yMMMd().add_jm();
          final event = post.kind == PostKind.communityEvent ? CommunityEvent.fromKindredPost(post) : null;
          final publicPath = _publicPath(post);
          final hasImage = post.imageUrl != null && post.imageUrl!.trim().isNotEmpty;

          // ScrollView spans full body width so trackpad/wheel/scrollbar hit the whole viewport;
          // content stays capped and centered inside.
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 28, 0, 48),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCol = constraints.maxWidth >= _twoColBreakpoint;
                      final imageBlock = _CoverPreview(
                        imageUrl: hasImage ? post.imageUrl!.trim() : null,
                        fixedWidth: twoCol ? _imageColumnWidth : null,
                        height: _imageHeight,
                      );

                      final detailColumn = _ReviewDetailColumn(
                        post: post,
                        event: event,
                        theme: theme,
                        fmt: fmt,
                        publicPath: publicPath,
                        onOpenPublic: () => context.push(publicPath),
                        onOpenAuthor: () => context.push('/u/${post.authorId}'),
                        onCopyPostId: () => _copy('post ID', post.id),
                        onCopyPublicPath: () => _copy('path', publicPath),
                        onStubTool: (name) => _snack('$name — not wired yet'),
                      );

                      if (twoCol) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            imageBlock,
                            const SizedBox(width: 32),
                            Expanded(child: detailColumn),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          imageBlock,
                          const SizedBox(height: 24),
                          detailColumn,
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({
    required this.imageUrl,
    required this.fixedWidth,
    required this.height,
  });

  final String? imageUrl;
  final double? fixedWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final inner = imageUrl == null
        ? ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          )
        : Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            width: fixedWidth ?? double.infinity,
            height: height,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.outline, size: 40),
            ),
          );

    return ClipRRect(
      borderRadius: radius,
      child: fixedWidth != null
          ? SizedBox(width: fixedWidth, height: height, child: inner)
          : SizedBox(width: double.infinity, height: height, child: inner),
    );
  }
}

class _ReviewDetailColumn extends StatelessWidget {
  const _ReviewDetailColumn({
    required this.post,
    required this.event,
    required this.theme,
    required this.fmt,
    required this.publicPath,
    required this.onOpenPublic,
    required this.onOpenAuthor,
    required this.onCopyPostId,
    required this.onCopyPublicPath,
    required this.onStubTool,
  });

  final KindredPost post;
  final CommunityEvent? event;
  final ThemeData theme;
  final DateFormat fmt;
  final String publicPath;
  final VoidCallback onOpenPublic;
  final VoidCallback onOpenAuthor;
  final VoidCallback onCopyPostId;
  final VoidCallback onCopyPublicPath;
  final void Function(String name) onStubTool;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final body = post.body?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text(postKindListHeadline(post.kind)),
              visualDensity: VisualDensity.compact,
              backgroundColor: postKindIconBadgeBackground(post.kind),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            Chip(
              label: Text(post.status == PostStatus.fulfilled ? 'Fulfilled' : 'Open'),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(
          post.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 20),
        _MetaTable(
          rows: [
            _MetaRowData('Post ID', post.id, monospace: true),
            _MetaRowData('Author', post.authorName),
            _MetaRowData('Author UID', post.authorId, monospace: true),
            _MetaRowData('Created', fmt.format(post.createdAt.toLocal())),
            if (event != null) _MetaRowData('Schedule', formatEventScheduleLine(event!)),
            if (post.locationDescription != null && post.locationDescription!.trim().isNotEmpty)
              _MetaRowData('Location', post.locationDescription!.trim()),
            _MetaRowData('Geohash', post.geohash, monospace: true),
          ],
        ),
        if (body != null && body.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Body', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5, color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 32),
        Text('Actions', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onOpenPublic,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open public page'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenAuthor,
              icon: const Icon(Icons.person_search_outlined, size: 18),
              label: const Text('Author profile'),
            ),
            OutlinedButton.icon(
              onPressed: onCopyPostId,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy post ID'),
            ),
            OutlinedButton.icon(
              onPressed: onCopyPublicPath,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Copy public path'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Moderation tools',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'These are placeholders until backend workflows exist.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(
              onPressed: () => onStubTool('Feature on home'),
              child: const Text('Feature on home'),
            ),
            OutlinedButton(
              onPressed: () => onStubTool('Hide from feed'),
              child: const Text('Hide from feed'),
            ),
            OutlinedButton(
              onPressed: () => onStubTool('Send warning to author'),
              child: const Text('Notify author'),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaRowData {
  const _MetaRowData(this.label, this.value, {this.monospace = false});

  final String label;
  final String value;
  final bool monospace;
}

class _MetaTable extends StatelessWidget {
  const _MetaTable({required this.rows});

  final List<_MetaRowData> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = BorderSide(color: theme.dividerColor.withValues(alpha: 0.5));

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.1),
        1: FlexColumnWidth(2.4),
      },
      border: TableBorder(horizontalInside: border, bottom: border, top: border),
      children: rows
          .map(
            (r) => TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Text(
                    r.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: SelectableText(
                    r.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: r.monospace ? 'monospace' : null,
                      fontSize: r.monospace ? 13 : null,
                    ),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}
