import 'package:cloud_firestore/cloud_firestore.dart';

import 'post_kind.dart';

enum PostStatus { open, fulfilled }

class KindredPost {
  const KindredPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.title,
    this.body,
    this.imageUrl,
    required this.geoPoint,
    required this.geohash,
    required this.status,
    this.fulfilledByUserId,
    required this.createdAt,
    this.startsAt,
    this.endsAt,
    this.locationDescription,
  });

  final String id;
  final String authorId;
  /// Denormalized for feed cards (no extra profile reads).
  final String authorName;
  final PostKind kind;
  final String title;
  final String? body;
  final String? imageUrl;
  final GeoPoint geoPoint;
  final String geohash;
  final PostStatus status;
  final String? fulfilledByUserId;
  final DateTime createdAt;
  /// Set when [kind] is [PostKind.communityEvent].
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? locationDescription;

  static KindredPost? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final kind = postKindFromFirestore(data['kind'] as String?);
    if (kind == null) return null;
    final gp = data['geoPoint'];
    if (gp is! GeoPoint) return null;
    final rawName = (data['authorName'] as String?)?.trim();
    final startsAt = (data['startsAt'] as Timestamp?)?.toDate();
    final endsAt = (data['endsAt'] as Timestamp?)?.toDate();
    final loc = (data['locationDescription'] as String?)?.trim();
    return KindredPost(
      id: doc.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: rawName != null && rawName.isNotEmpty ? rawName : 'Neighbor',
      kind: kind,
      title: data['title'] as String? ?? '',
      body: data['body'] as String?,
      imageUrl: data['imageUrl'] as String?,
      geoPoint: gp,
      geohash: data['geohash'] as String? ?? '',
      status: (data['status'] as String?) == 'fulfilled' ? PostStatus.fulfilled : PostStatus.open,
      fulfilledByUserId: data['fulfilledByUserId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      startsAt: startsAt,
      endsAt: endsAt,
      locationDescription: loc != null && loc.isNotEmpty ? loc : null,
    );
  }

  Map<String, dynamic> toCreateMap() {
    final base = <String, dynamic>{
      'authorId': authorId,
      'authorName': authorName,
      'kind': postKindToFirestore(kind),
      'title': title,
      if (body != null && body!.isNotEmpty) 'body': body,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty) 'imageUrl': imageUrl!.trim(),
      'geoPoint': geoPoint,
      'geohash': geohash,
      'status': status == PostStatus.fulfilled ? 'fulfilled' : 'open',
      if (fulfilledByUserId != null) 'fulfilledByUserId': fulfilledByUserId,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
    if (kind == PostKind.communityEvent) {
      if (startsAt != null) {
        base['startsAt'] = Timestamp.fromDate(startsAt!);
      }
      if (endsAt != null) {
        base['endsAt'] = Timestamp.fromDate(endsAt!);
      }
      if (locationDescription != null && locationDescription!.trim().isNotEmpty) {
        base['locationDescription'] = locationDescription!.trim();
      }
    }
    return base;
  }
}
