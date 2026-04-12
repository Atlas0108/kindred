import 'package:cloud_firestore/cloud_firestore.dart';

/// Incoming request stored at `users/{recipientUid}/connectionRequests/{fromUserId}`.
class ConnectionRequest {
  const ConnectionRequest({
    required this.fromUserId,
    required this.fromDisplayName,
    required this.createdAt,
  });

  final String fromUserId;
  final String fromDisplayName;
  final DateTime createdAt;

  static ConnectionRequest? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final fromRaw = (data['fromUserId'] as String?)?.trim();
    final from = (fromRaw != null && fromRaw.isNotEmpty) ? fromRaw : doc.id.trim();
    if (from.isEmpty) return null;
    final name = (data['fromDisplayName'] as String?)?.trim();
    return ConnectionRequest(
      fromUserId: from,
      fromDisplayName: (name != null && name.isNotEmpty) ? name : 'Neighbor',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
