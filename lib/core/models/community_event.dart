import 'package:cloud_firestore/cloud_firestore.dart';

import 'post.dart';
import 'post_kind.dart';

class CommunityEvent {
  const CommunityEvent({
    required this.id,
    required this.organizerId,
    required this.title,
    required this.description,
    this.imageUrl,
    required this.startsAt,
    required this.endsAt,
    required this.organizerName,
    required this.locationDescription,
    required this.geoPoint,
    required this.geohash,
    required this.createdAt,
  });

  final String id;
  final String organizerId;
  final String title;
  final String description;
  final String? imageUrl;
  final DateTime startsAt;
  /// End time; may be absent on legacy documents (treat as unknown).
  final DateTime? endsAt;
  /// Host-facing name or group (not the same as [organizerId]).
  final String organizerName;
  /// Street address, venue name, and/or virtual meeting link as entered by the organizer.
  final String locationDescription;
  final GeoPoint geoPoint;
  final String geohash;
  final DateTime createdAt;

  /// Event posts use [KindredPost] in the `posts` collection with [PostKind.communityEvent].
  /// Resolves either a legacy `events` document or a `posts` doc with [PostKind.communityEvent].
  static CommunityEvent? fromFirestoreDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    if (data['kind'] == 'community_event') {
      final p = KindredPost.fromDoc(doc);
      return p == null ? null : CommunityEvent.fromKindredPost(p);
    }
    if (data.containsKey('kind')) return null;
    return CommunityEvent.fromDoc(doc);
  }

  static CommunityEvent? fromKindredPost(KindredPost p) {
    if (p.kind != PostKind.communityEvent) return null;
    final start = p.startsAt ?? p.createdAt;
    return CommunityEvent(
      id: p.id,
      organizerId: p.authorId,
      title: p.title,
      description: p.body?.trim() ?? '',
      imageUrl: p.imageUrl,
      startsAt: start,
      endsAt: p.endsAt,
      organizerName: p.authorName,
      locationDescription: p.locationDescription ?? '',
      geoPoint: p.geoPoint,
      geohash: p.geohash,
      createdAt: p.createdAt,
    );
  }

  static CommunityEvent? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final gp = data['geoPoint'];
    if (gp is! GeoPoint) return null;
    return CommunityEvent(
      id: doc.id,
      organizerId: data['organizerId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      startsAt: (data['startsAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endsAt: (data['endsAt'] as Timestamp?)?.toDate(),
      organizerName: (data['organizerName'] as String?)?.trim() ?? '',
      locationDescription: (data['locationDescription'] as String?)?.trim() ?? '',
      geoPoint: gp,
      geohash: data['geohash'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toCreateMap() {
    final end = endsAt;
    if (end == null) {
      throw StateError('New events must include endsAt');
    }
    return {
      'organizerId': organizerId,
      'title': title,
      'description': description,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty) 'imageUrl': imageUrl!.trim(),
      'startsAt': Timestamp.fromDate(startsAt),
      'endsAt': Timestamp.fromDate(end),
      'organizerName': organizerName,
      'locationDescription': locationDescription,
      'geoPoint': geoPoint,
      'geohash': geohash,
      // Client Timestamp avoids waiting on serverTimestamp resolution on some web clients.
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
  }
}
