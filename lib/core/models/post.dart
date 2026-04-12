import 'package:cloud_firestore/cloud_firestore.dart';

import 'post_kind.dart';

enum PostStatus { open, fulfilled }

class KindredPost {
  const KindredPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.tags,
    required this.title,
    this.body,
    this.imageUrl,
    required this.geoPoint,
    required this.geohash,
    required this.status,
    this.linkedRequestId,
    this.fulfilledByUserId,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  /// Denormalized for feed cards (no extra profile reads).
  final String authorName;
  final PostKind kind;
  final List<String> tags;
  final String title;
  final String? body;
  final String? imageUrl;
  final GeoPoint geoPoint;
  final String geohash;
  final PostStatus status;
  final String? linkedRequestId;
  final String? fulfilledByUserId;
  final DateTime createdAt;

  static KindredPost? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final kind = postKindFromFirestore(data['kind'] as String?);
    if (kind == null) return null;
    final gp = data['geoPoint'];
    if (gp is! GeoPoint) return null;
    final rawName = (data['authorName'] as String?)?.trim();
    return KindredPost(
      id: doc.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: rawName != null && rawName.isNotEmpty ? rawName : 'Neighbor',
      kind: kind,
      tags: List<String>.from(data['tags'] as List<dynamic>? ?? const []),
      title: data['title'] as String? ?? '',
      body: data['body'] as String?,
      imageUrl: data['imageUrl'] as String?,
      geoPoint: gp,
      geohash: data['geohash'] as String? ?? '',
      status: (data['status'] as String?) == 'fulfilled' ? PostStatus.fulfilled : PostStatus.open,
      linkedRequestId: data['linkedRequestId'] as String?,
      fulfilledByUserId: data['fulfilledByUserId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'kind': postKindToFirestore(kind),
      'tags': tags,
      'title': title,
      if (body != null && body!.isNotEmpty) 'body': body,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty) 'imageUrl': imageUrl!.trim(),
      'geoPoint': geoPoint,
      'geohash': geohash,
      'status': status == PostStatus.fulfilled ? 'fulfilled' : 'open',
      if (linkedRequestId != null) 'linkedRequestId': linkedRequestId,
      if (fulfilledByUserId != null) 'fulfilledByUserId': fulfilledByUserId,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
  }
}
