import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../kindred_trace.dart';
import '../geo/geo_utils.dart';
import '../models/post.dart';
import '../models/post_kind.dart';

class PostService {
  PostService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _uuid = const Uuid();

  static const Duration _writeAckWait = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  /// Newest posts first (for Home). Same ordering as [postsInRadius] but without geo filter.
  Stream<List<KindredPost>> homePostsFeed({int limit = 50}) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs.map(KindredPost.fromDoc).whereType<KindredPost>().toList(),
        );
  }

  Stream<List<KindredPost>> postsInRadius({
    required GeoPoint center,
    required double radiusMiles,
    int limit = 200,
  }) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = <KindredPost>[];
      for (final doc in snap.docs) {
        final p = KindredPost.fromDoc(doc);
        if (p == null) continue;
        if (withinRadiusMiles(center, p.geoPoint, radiusMiles)) {
          list.add(p);
        }
      }
      return list;
    });
  }

  Future<String> createPost({
    required PostKind kind,
    required String title,
    String? body,
    required List<String> tags,
    required GeoPoint geoPoint,
  }) async {
    kindredTrace('PostService.createPost enter', title);
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final id = _uuid.v4();
    kindredTrace('PostService.createPost doc id', id);
    final post = KindredPost(
      id: id,
      authorId: user.uid,
      kind: kind,
      tags: tags,
      title: title,
      body: body,
      geoPoint: geoPoint,
      geohash: encodeGeohash(geoPoint.latitude, geoPoint.longitude),
      status: PostStatus.open,
      createdAt: DateTime.now(),
    );
    kindredTrace('PostService.createPost before posts/$id .set()');
    try {
      await _posts.doc(id).set(post.toCreateMap()).timeout(_writeAckWait);
      kindredTrace('PostService.createPost after .set() OK');
    } on TimeoutException {
      kindredTrace(
        'PostService.createPost .set() timed out',
        'continuing with $id — write may still complete in background',
      );
    }
    return id;
  }

  Future<void> markFulfilledWithThankYou({
    required KindredPost request,
    String? helperUserId,
    bool createThankYouPost = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (request.authorId != user.uid) {
      throw StateError('Only the author can mark this fulfilled');
    }
    if (request.kind != PostKind.helpRequest) {
      throw StateError('Not a help request');
    }
    if (request.status == PostStatus.fulfilled) {
      return;
    }

    final batch = _firestore.batch();
    final postRef = _posts.doc(request.id);
    batch.update(postRef, {
      'status': 'fulfilled',
      if (helperUserId != null) 'fulfilledByUserId': helperUserId,
    });

    if (createThankYouPost) {
      final thankId = _uuid.v4();
      final thankRef = _posts.doc(thankId);
      final thank = KindredPost(
        id: thankId,
        authorId: user.uid,
        kind: PostKind.thankYou,
        tags: const ['thank you'],
        title: 'Thank you for helping with: ${request.title}',
        body: null,
        geoPoint: request.geoPoint,
        geohash: request.geohash,
        status: PostStatus.open,
        linkedRequestId: request.id,
        createdAt: DateTime.now(),
      );
      batch.set(thankRef, thank.toCreateMap());
    }

    await batch.commit();
  }
}
