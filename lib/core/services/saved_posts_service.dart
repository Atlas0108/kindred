import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/community_event.dart';
import '../models/post.dart';
import '../models/post_kind.dart';

class SavedPostsService {
  SavedPostsService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _savedRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('savedPosts');

  /// Document ids are the saved content id (same as `posts` or legacy `events` doc id).
  Stream<Set<String>> savedIdsStream() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<Set<String>>.value({});
      }
      return _savedRef(user.uid).snapshots().map(
            (s) => s.docs.map((d) => d.id).toSet(),
          );
    });
  }

  Future<void> toggleSave(String contentId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ref = _savedRef(user.uid).doc(contentId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
    } else {
      await ref.set({
        'postId': contentId,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Newest saves first. Resolves each id against `posts` then legacy `events`.
  Stream<List<KindredPost>> savedPostsFeed({int limit = 50}) {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<KindredPost>>.value([]);
      }
      return _savedRef(user.uid)
          .orderBy('savedAt', descending: true)
          .limit(limit)
          .snapshots()
          .asyncMap(_resolveDocsInOrder);
    });
  }

  Future<List<KindredPost>> _resolveDocsInOrder(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (snap.docs.isEmpty) return [];
    final postsCol = _firestore.collection('posts');
    final eventsCol = _firestore.collection('events');
    final out = <KindredPost>[];
    for (final saved in snap.docs) {
      final id = saved.id;
      final pDoc = await postsCol.doc(id).get();
      if (pDoc.exists) {
        final p = KindredPost.fromDoc(pDoc);
        if (p != null) out.add(p);
        continue;
      }
      final eDoc = await eventsCol.doc(id).get();
      if (eDoc.exists) {
        final e = CommunityEvent.fromDoc(eDoc);
        final p = e == null ? null : _legacyEventAsKindredPost(e);
        if (p != null) out.add(p);
      }
    }
    return out;
  }

  KindredPost _legacyEventAsKindredPost(CommunityEvent e) {
    return KindredPost(
      id: e.id,
      authorId: e.organizerId,
      authorName: e.organizerName.trim().isNotEmpty ? e.organizerName.trim() : 'Neighbor',
      kind: PostKind.communityEvent,
      title: e.title,
      body: e.description,
      imageUrl: e.imageUrl,
      geoPoint: e.geoPoint,
      geohash: e.geohash,
      status: PostStatus.open,
      createdAt: e.createdAt,
      startsAt: e.startsAt,
      endsAt: e.endsAt,
      locationDescription: e.locationDescription.trim().isNotEmpty ? e.locationDescription.trim() : null,
    );
  }
}
