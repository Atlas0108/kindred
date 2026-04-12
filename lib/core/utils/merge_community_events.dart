import '../models/community_event.dart';
import '../models/post.dart';
import '../models/post_kind.dart';

/// Combines legacy `events` documents with [PostKind.communityEvent] posts (same radius filter
/// must already be applied to both inputs). Post-backed entries win on id collision.
List<CommunityEvent> mergeLegacyAndPostEventRows(
  List<CommunityEvent> legacyInRadius,
  List<KindredPost> postsInRadius,
) {
  final fromPosts = postsInRadius
      .where((p) => p.kind == PostKind.communityEvent)
      .map(CommunityEvent.fromKindredPost)
      .whereType<CommunityEvent>()
      .toList();
  final byId = <String, CommunityEvent>{};
  for (final e in legacyInRadius) {
    byId[e.id] = e;
  }
  for (final e in fromPosts) {
    byId[e.id] = e;
  }
  final list = byId.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return list;
}
