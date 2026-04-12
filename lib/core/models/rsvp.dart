import 'package:cloud_firestore/cloud_firestore.dart';

enum RsvpStatus { going, maybe, declined }

String rsvpStatusToFirestore(RsvpStatus s) {
  switch (s) {
    case RsvpStatus.going:
      return 'going';
    case RsvpStatus.maybe:
      return 'maybe';
    case RsvpStatus.declined:
      return 'declined';
  }
}

RsvpStatus? rsvpStatusFromFirestore(String? v) {
  switch (v) {
    case 'going':
      return RsvpStatus.going;
    case 'maybe':
      return RsvpStatus.maybe;
    case 'declined':
      return RsvpStatus.declined;
    default:
      return null;
  }
}

class EventRsvp {
  const EventRsvp({
    required this.userId,
    required this.status,
    required this.updatedAt,
  });

  final String userId;
  final RsvpStatus status;
  final DateTime updatedAt;

  static EventRsvp? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final st = rsvpStatusFromFirestore(data['status'] as String?);
    if (st == null) return null;
    return EventRsvp(
      userId: data['userId'] as String? ?? doc.id,
      status: st,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toWriteMap() {
    return {
      'userId': userId,
      'status': rsvpStatusToFirestore(status),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
