import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../kindred_trace.dart';
import '../geo/geo_utils.dart';
import '../models/post.dart';
import '../models/post_kind.dart';
import '../utils/cover_image_prepare.dart';

class PostService {
  PostService(this._firestore, this._auth, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  static const Duration _writeAckWait = Duration(seconds: 15);

  static const Duration _storagePutTimeout = Duration(seconds: 180);
  static const Duration _storageUrlTimeout = Duration(seconds: 45);

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

  Future<String> _authorDisplayName(User user) async {
    final dn = user.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final fromProfile = doc.data()?['displayName'] as String?;
      final t = fromProfile?.trim();
      if (t != null && t.isNotEmpty) return t;
    } on Exception catch (e) {
      kindredTrace('PostService._authorDisplayName profile read', e);
    }
    return 'Neighbor';
  }

  Future<String> _awaitUploadTask(UploadTask task, Reference ref, String logLabel) async {
    try {
      await task.timeout(
        _storagePutTimeout,
        onTimeout: () async {
          try {
            await task.cancel();
          } on Object catch (_) {}
          throw TimeoutException(
            'Image upload timed out after ${_storagePutTimeout.inSeconds}s. '
            'Deploy rules to this bucket: firebase deploy --only storage. '
            'Set CORS: gsutil cors set storage-cors.json gs://gathr-5b405.firebasestorage.app',
          );
        },
      );
    } on FirebaseException catch (e) {
      kindredTrace('PostService._awaitUploadTask FirebaseException', '${e.code} ${e.message}');
      rethrow;
    }
    kindredTrace('PostService._awaitUploadTask put complete', logLabel);
    return ref.getDownloadURL().timeout(
      _storageUrlTimeout,
      onTimeout: () => throw TimeoutException(
        'Got upload response but timed out fetching the download URL.',
      ),
    );
  }

  /// [webImageBlob] is a JS `Blob` from [blobFromObjectUrl] on web; avoids huge `Uint8List` → JS copies.
  Future<String> _uploadPostCoverImage({
    required String postId,
    Uint8List? bytes,
    Object? webImageBlob,
    required String contentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final mime = contentType.trim().isEmpty ? 'image/jpeg' : contentType.trim();

    if (webImageBlob != null) {
      kindredTrace('PostService._uploadPostCoverImage putBlob (web)', postId);
      final ext = mime.toLowerCase().contains('png') ? 'png' : 'jpg';
      final ref = _storage.ref('post_images/${user.uid}/$postId.$ext');
      final task = ref.putBlob(
        webImageBlob,
        SettableMetadata(contentType: mime),
      );
      return _awaitUploadTask(task, ref, postId);
    }

    if (bytes == null || bytes.isEmpty) {
      throw ArgumentError('image bytes or web blob required');
    }

    final prepared = await prepareCoverImageForUploadAsync(bytes, mime);
    kindredTrace(
      'PostService._uploadPostCoverImage prepared',
      '${prepared.bytes.length} bytes (was ${bytes.length})',
    );
    final ext = prepared.contentType.toLowerCase().contains('png') ? 'png' : 'jpg';
    final ref = _storage.ref('post_images/${user.uid}/$postId.$ext');
    final task = ref.putData(
      prepared.bytes,
      SettableMetadata(contentType: prepared.contentType),
    );
    return _awaitUploadTask(task, ref, postId);
  }

  Future<String> createPost({
    required PostKind kind,
    required String title,
    String? body,
    required List<String> tags,
    required GeoPoint geoPoint,
    Uint8List? imageBytes,
    String? imageContentType,
    Object? webImageBlob,
  }) async {
    kindredTrace('PostService.createPost enter', title);
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final id = _uuid.v4();
    kindredTrace('PostService.createPost doc id', id);
    final authorName = await _authorDisplayName(user);
    String? imageUrl;
    final mime = (imageContentType != null && imageContentType.trim().isNotEmpty)
        ? imageContentType.trim()
        : 'image/jpeg';
    final hasBlob = webImageBlob != null;
    final hasBytes = imageBytes != null && imageBytes.isNotEmpty;
    if (hasBlob || hasBytes) {
      kindredTrace(
        'PostService.createPost uploading image',
        hasBlob ? 'web Blob' : '${imageBytes?.length ?? 0} bytes',
      );
      imageUrl = await _uploadPostCoverImage(
        postId: id,
        bytes: hasBlob ? null : imageBytes,
        webImageBlob: hasBlob ? webImageBlob : null,
        contentType: mime,
      );
    }
    final post = KindredPost(
      id: id,
      authorId: user.uid,
      authorName: authorName,
      kind: kind,
      tags: tags,
      title: title,
      body: body,
      imageUrl: imageUrl,
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
      final thankAuthor = await _authorDisplayName(user);
      final thank = KindredPost(
        id: thankId,
        authorId: user.uid,
        authorName: thankAuthor,
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
