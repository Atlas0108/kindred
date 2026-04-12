import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../kindred_trace.dart';
import '../geo/geo_utils.dart';
import '../models/community_event.dart';
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

  /// Newest events first (for Home). Requires [CommunityEvent.createdAt] on documents.
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
    final event = CommunityEvent(
      id: id,
      organizerId: user.uid,
      title: title,
      description: description,
      imageUrl: imageUrl,
      startsAt: startsAt,
      endsAt: endsAt,
      organizerName: organizerName,
      tags: tags,
      locationDescription: locationDescription,
      geoPoint: geoPoint,
      geohash: encodeGeohash(geoPoint.latitude, geoPoint.longitude),
      createdAt: DateTime.now(),
    );
    kindredTrace('EventService.createEvent before events/$id .set()');
    try {
      await _events.doc(id).set(event.toCreateMap()).timeout(_writeAckWait);
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
    return _events.doc(eventId).collection('rsvps').doc(user.uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return EventRsvp.fromDoc(doc);
    });
  }

  Stream<List<EventRsvp>> rsvpsStream(String eventId) {
    return _events.doc(eventId).collection('rsvps').snapshots().map((snap) {
      return snap.docs.map(EventRsvp.fromDoc).whereType<EventRsvp>().toList();
    });
  }

  Future<void> setMyRsvp(String eventId, RsvpStatus status) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final rsvp = EventRsvp(userId: user.uid, status: status, updatedAt: DateTime.now());
    await _events
        .doc(eventId)
        .collection('rsvps')
        .doc(user.uid)
        .set(rsvp.toWriteMap());
  }
}
