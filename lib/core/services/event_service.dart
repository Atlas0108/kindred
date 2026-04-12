import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../kindred_trace.dart';
import '../geo/geo_utils.dart';
import '../models/community_event.dart';
import '../models/post.dart';
import '../models/post_kind.dart';
import '../models/rsvp.dart';
import '../utils/cover_image_prepare.dart';

class EventService {
  EventService(this._firestore, this._auth, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  /// Max time to wait for Firestore to acknowledge a write. On web the Future can stall
  /// even when the document is saved; we still return the known [id] after this.
  static const Duration _writeAckWait = Duration(seconds: 15);

  static const Duration _storagePutTimeout = Duration(seconds: 180);
  static const Duration _storageUrlTimeout = Duration(seconds: 45);

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('events');

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  /// Whether this id refers to a community-event post in `posts` vs a legacy `events` doc.
  Future<DocumentReference<Map<String, dynamic>>> resolveEventDocumentRef(String id) async {
    final postSnap = await _posts.doc(id).get();
    if (postSnap.exists && postSnap.data()?['kind'] == 'community_event') {
      return _posts.doc(id);
    }
    return _events.doc(id);
  }

  /// Listens to the correct backing document (post-backed event or legacy `events` doc).
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchEventDocument(String eventId) async* {
    final postRef = _posts.doc(eventId);
    final postSnap = await postRef.get();
    if (postSnap.exists && postSnap.data()?['kind'] == 'community_event') {
      yield* postRef.snapshots();
      return;
    }
    yield* _events.doc(eventId).snapshots();
  }

  /// For edit screens: load from `posts` (event kind) or legacy `events`.
  Future<CommunityEvent?> fetchEvent(String id) async {
    final postSnap = await _posts.doc(id).get();
    if (postSnap.exists && postSnap.data()?['kind'] == 'community_event') {
      final p = KindredPost.fromDoc(postSnap);
      return p == null ? null : CommunityEvent.fromKindredPost(p);
    }
    final leg = await _events.doc(id).get();
    return CommunityEvent.fromDoc(leg);
  }

  /// Legacy `events` documents only. Merge with [PostService.postsInRadius] and
  /// [mergeLegacyAndPostEventRows] to include [PostKind.communityEvent] posts.
  Stream<List<CommunityEvent>> eventsInRadius({
    required GeoPoint center,
    required double radiusMiles,
    int limit = 200,
  }) {
    return _events
        .orderBy('startsAt', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = <CommunityEvent>[];
      for (final doc in snap.docs) {
        final e = CommunityEvent.fromDoc(doc);
        if (e == null) continue;
        if (withinRadiusMiles(center, e.geoPoint, radiusMiles)) {
          list.add(e);
        }
      }
      return list;
    });
  }

  /// Newest first from the legacy `events` collection only (older data). New events are [PostKind.communityEvent] in `posts` — see [PostService.homePostsFeed].
  Stream<List<CommunityEvent>> homeEventsFeed({int limit = 50}) {
    return _events
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(CommunityEvent.fromDoc)
              .whereType<CommunityEvent>()
              .toList(),
        );
  }

  /// Events you organize, newest [CommunityEvent.createdAt] first (no composite index;
  /// sorted client-side like [PostService.myPostsFeed]).
  Stream<List<CommunityEvent>> myOrganizedEventsFeed({int limit = 50}) {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<CommunityEvent>>.value([]);
      }
      return _events
          .where('organizerId', isEqualTo: user.uid)
          .limit(limit)
          .snapshots()
          .map((snap) {
            final list = snap.docs.map(CommunityEvent.fromDoc).whereType<CommunityEvent>().toList();
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });
    });
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
            'Deploy rules: firebase deploy --only storage. '
            'CORS: gsutil cors set storage-cors.json gs://gathr-5b405.firebasestorage.app',
          );
        },
      );
    } on FirebaseException catch (e) {
      kindredTrace('EventService._awaitUploadTask FirebaseException', '${e.code} ${e.message}');
      rethrow;
    }
    kindredTrace('EventService._awaitUploadTask put complete', logLabel);
    return ref.getDownloadURL().timeout(
      _storageUrlTimeout,
      onTimeout: () => throw TimeoutException(
        'Got upload response but timed out fetching the download URL.',
      ),
    );
  }

  Future<String> _uploadEventCoverImage({
    required String eventId,
    Uint8List? bytes,
    Object? webImageBlob,
    required String contentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final mime = contentType.trim().isEmpty ? 'image/jpeg' : contentType.trim();

    if (webImageBlob != null) {
      kindredTrace('EventService._uploadEventCoverImage putBlob (web)', eventId);
      final ext = mime.toLowerCase().contains('png') ? 'png' : 'jpg';
      final ref = _storage.ref('event_images/${user.uid}/$eventId.$ext');
      final task = ref.putBlob(
        webImageBlob,
        SettableMetadata(contentType: mime),
      );
      return _awaitUploadTask(task, ref, eventId);
    }

    if (bytes == null || bytes.isEmpty) {
      throw ArgumentError('image bytes or web blob required');
    }

    final prepared = await prepareCoverImageForUploadAsync(bytes, mime);
    kindredTrace(
      'EventService._uploadEventCoverImage prepared',
      '${prepared.bytes.length} bytes (was ${bytes.length})',
    );
    final ext = prepared.contentType.toLowerCase().contains('png') ? 'png' : 'jpg';
    final ref = _storage.ref('event_images/${user.uid}/$eventId.$ext');
    final task = ref.putData(
      prepared.bytes,
      SettableMetadata(contentType: prepared.contentType),
    );
    return _awaitUploadTask(task, ref, eventId);
  }

  Future<String> createEvent({
    required String title,
    required String description,
    required String organizerName,
    required List<String> tags,
    required DateTime startsAt,
    required DateTime endsAt,
    required String locationDescription,
    required GeoPoint geoPoint,
    Uint8List? imageBytes,
    String? imageContentType,
    Object? webImageBlob,
  }) async {
    kindredTrace('EventService.createEvent enter', title);
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError.value(endsAt, 'endsAt', 'must be after startsAt');
    }
    final id = _uuid.v4();
    kindredTrace('EventService.createEvent doc id', id);
    String? imageUrl;
    final mime = (imageContentType != null && imageContentType.trim().isNotEmpty)
        ? imageContentType.trim()
        : 'image/jpeg';
    final hasBlob = webImageBlob != null;
    final hasBytes = imageBytes != null && imageBytes.isNotEmpty;
    if (hasBlob || hasBytes) {
      kindredTrace(
        'EventService.createEvent uploading image',
        hasBlob ? 'web Blob' : '${imageBytes?.length ?? 0} bytes',
      );
      imageUrl = await _uploadEventCoverImage(
        eventId: id,
        bytes: hasBlob ? null : imageBytes,
        webImageBlob: hasBlob ? webImageBlob : null,
        contentType: mime,
      );
    }
    final post = KindredPost(
      id: id,
      authorId: user.uid,
      authorName: organizerName.trim().isNotEmpty ? organizerName.trim() : 'Neighbor',
      kind: PostKind.communityEvent,
      tags: tags,
      title: title,
      body: description,
      imageUrl: imageUrl,
      geoPoint: geoPoint,
      geohash: encodeGeohash(geoPoint.latitude, geoPoint.longitude),
      status: PostStatus.open,
      createdAt: DateTime.now(),
      startsAt: startsAt,
      endsAt: endsAt,
      locationDescription: locationDescription.trim().isNotEmpty ? locationDescription.trim() : null,
    );
    kindredTrace('EventService.createEvent before posts/$id .set()');
    try {
      await _posts.doc(id).set(post.toCreateMap()).timeout(_writeAckWait);
      kindredTrace('EventService.createEvent after .set() OK');
    } on TimeoutException {
      kindredTrace(
        'EventService.createEvent .set() timed out',
        'continuing with $id — write may still complete in background',
      );
    }
    return id;
  }

  Stream<EventRsvp?> myRsvpStream(String eventId) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    final uid = user.uid;
    return Stream.fromFuture(resolveEventDocumentRef(eventId)).asyncExpand((root) {
      return root.collection('rsvps').doc(uid).snapshots().map((doc) {
        if (!doc.exists) return null;
        return EventRsvp.fromDoc(doc);
      });
    });
  }

  Stream<List<EventRsvp>> rsvpsStream(String eventId) {
    return Stream.fromFuture(resolveEventDocumentRef(eventId)).asyncExpand((root) {
      return root.collection('rsvps').snapshots().map((snap) {
        return snap.docs.map(EventRsvp.fromDoc).whereType<EventRsvp>().toList();
      });
    });
  }

  Future<void> setMyRsvp(String eventId, RsvpStatus status) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final root = await resolveEventDocumentRef(eventId);
    final rsvp = EventRsvp(userId: user.uid, status: status, updatedAt: DateTime.now());
    await root.collection('rsvps').doc(user.uid).set(rsvp.toWriteMap());
  }

  Future<void> updateEvent({
    required CommunityEvent event,
    required String title,
    required String description,
    required String organizerName,
    required List<String> tags,
    required DateTime startsAt,
    required DateTime endsAt,
    required String locationDescription,
    required GeoPoint geoPoint,
    bool userRemovedCover = false,
    Uint8List? newCoverBytes,
    Object? newCoverWebBlob,
    String? newCoverContentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (event.organizerId != user.uid) {
      throw StateError('Only the organizer can edit this event');
    }
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError.value(endsAt, 'endsAt', 'must be after startsAt');
    }

    final hasNewCover =
        newCoverWebBlob != null || (newCoverBytes != null && newCoverBytes.isNotEmpty);

    final ref = await resolveEventDocumentRef(event.id);
    final isPostBacked = ref.path.startsWith('posts/');

    final data = <String, dynamic>{
      'title': title.trim(),
      'tags': tags,
      'startsAt': Timestamp.fromDate(startsAt),
      'endsAt': Timestamp.fromDate(endsAt),
      'locationDescription': locationDescription.trim(),
      'geoPoint': geoPoint,
      'geohash': encodeGeohash(geoPoint.latitude, geoPoint.longitude),
    };

    if (isPostBacked) {
      data['body'] = description.trim();
      data['authorName'] = organizerName.trim();
    } else {
      data['description'] = description.trim();
      data['organizerName'] = organizerName.trim();
    }

    if (hasNewCover) {
      await _tryDeleteEventCoverInStorage(event, user.uid);
      final mime = (newCoverContentType != null && newCoverContentType.trim().isNotEmpty)
          ? newCoverContentType.trim()
          : 'image/jpeg';
      final url = await _uploadEventCoverImage(
        eventId: event.id,
        bytes: newCoverWebBlob != null ? null : newCoverBytes,
        webImageBlob: newCoverWebBlob,
        contentType: mime,
      );
      data['imageUrl'] = url;
    } else if (userRemovedCover) {
      await _tryDeleteEventCoverInStorage(event, user.uid);
      data['imageUrl'] = FieldValue.delete();
    }

    await ref.update(data).timeout(_writeAckWait);
  }

  /// Deletes the event, its RSVP subdocuments, and the cover image in Storage when possible.
  Future<void> deleteEvent(CommunityEvent event) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (event.organizerId != user.uid) {
      throw StateError('Only the organizer can delete this event');
    }

    await _tryDeleteEventCoverInStorage(event, user.uid);

    final eventRef = await resolveEventDocumentRef(event.id);
    final rsvpSnap = await eventRef.collection('rsvps').get();
    WriteBatch batch = _firestore.batch();
    var n = 0;
    for (final d in rsvpSnap.docs) {
      batch.delete(d.reference);
      n++;
      if (n >= 450) {
        await batch.commit();
        batch = _firestore.batch();
        n = 0;
      }
    }
    batch.delete(eventRef);
    await batch.commit().timeout(_writeAckWait);
  }

  Future<void> _tryDeleteEventCoverInStorage(CommunityEvent event, String uid) async {
    final url = event.imageUrl?.trim();
    if (url == null || url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        kindredTrace('EventService.deleteEvent storage refFromURL', '${e.code} ${e.message}');
      }
    } catch (e) {
      kindredTrace('EventService.deleteEvent storage refFromURL', e);
    }
    for (final ext in ['jpg', 'png']) {
      try {
        await _storage.ref('event_images/$uid/${event.id}.$ext').delete();
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          kindredTrace('EventService.deleteEvent storage path', '${e.code} ${e.message}');
        }
      }
    }
  }
}
