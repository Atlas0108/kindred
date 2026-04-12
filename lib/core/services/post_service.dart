import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../kindred_trace.dart';
import '../geo/geo_utils.dart';
import '../models/user_profile.dart';
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

  /// Current user’s posts, newest first (sorted client-side so no composite index is required).
  ///
  /// Tied to [FirebaseAuth.authStateChanges] so we resubscribe after auth restores; using
  /// [FirebaseAuth.currentUser] only once would yield [Stream.empty] and never update.
  Stream<List<KindredPost>> myPostsFeed({int limit = 50}) {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<KindredPost>>.value([]);
      }
      return _posts
          .where('authorId', isEqualTo: user.uid)
          .limit(limit)
          .snapshots()
          .map((snap) {
            final list = snap.docs.map(KindredPost.fromDoc).whereType<KindredPost>().toList();
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });
    });
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
    final em = user.email?.trim();
    final dn = user.displayName?.trim();
    if (dn != null && dn.isNotEmpty && dn != em) return dn;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        final p = UserProfile.fromDoc(user.uid, data);
        final label = p.publicDisplayLabel.trim();
        if (label.isNotEmpty && label != 'Neighbor') return label;
      }
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

  Future<void> updatePost({
    required KindredPost post,
    required PostKind kind,
    required String title,
    String? body,
    required List<String> tags,
    required GeoPoint geoPoint,
    bool userRemovedCover = false,
    Uint8List? newCoverBytes,
    Object? newCoverWebBlob,
    String? newCoverContentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (post.authorId != user.uid) {
      throw StateError('Only the author can edit this post');
    }

    final hasNewCover =
        newCoverWebBlob != null || (newCoverBytes != null && newCoverBytes.isNotEmpty);

    final data = <String, dynamic>{
      'kind': postKindToFirestore(kind),
      'title': title.trim(),
      'tags': tags,
      'geoPoint': geoPoint,
      'geohash': encodeGeohash(geoPoint.latitude, geoPoint.longitude),
    };

    final bodyTrim = body?.trim();
    if (bodyTrim != null && bodyTrim.isNotEmpty) {
      data['body'] = bodyTrim;
    } else {
      data['body'] = FieldValue.delete();
    }

    if (hasNewCover) {
      await _tryDeletePostCoverInStorage(post, user.uid);
      final mime = (newCoverContentType != null && newCoverContentType.trim().isNotEmpty)
          ? newCoverContentType.trim()
          : 'image/jpeg';
      final url = await _uploadPostCoverImage(
        postId: post.id,
        bytes: newCoverWebBlob != null ? null : newCoverBytes,
        webImageBlob: newCoverWebBlob,
        contentType: mime,
      );
      data['imageUrl'] = url;
    } else if (userRemovedCover) {
      await _tryDeletePostCoverInStorage(post, user.uid);
      data['imageUrl'] = FieldValue.delete();
    }

    await _posts.doc(post.id).update(data).timeout(_writeAckWait);
  }

  /// Removes the post document and, when possible, its cover image in Storage.
  Future<void> deletePost(KindredPost post) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (post.authorId != user.uid) {
      throw StateError('Only the author can delete this post');
    }

    await _tryDeletePostCoverInStorage(post, user.uid);
    await _posts.doc(post.id).delete().timeout(_writeAckWait);
  }

  Future<void> _tryDeletePostCoverInStorage(KindredPost post, String uid) async {
    final url = post.imageUrl?.trim();
    if (url == null || url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        kindredTrace('PostService.deletePost storage refFromURL', '${e.code} ${e.message}');
      }
    } catch (e) {
      kindredTrace('PostService.deletePost storage refFromURL', e);
    }
    for (final ext in ['jpg', 'png']) {
      try {
        await _storage.ref('post_images/$uid/${post.id}.$ext').delete();
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          kindredTrace('PostService.deletePost storage path', '${e.code} ${e.message}');
        }
      }
    }
  }
}
