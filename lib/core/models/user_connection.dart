import 'package:cloud_firestore/cloud_firestore.dart';

/// Accepted connection at `users/{uid}/connections/{peerUid}`.
class UserConnection {
  const UserConnection({
    required this.peerId,
    required this.peerDisplayName,
    required this.connectedAt,
  });

  final String peerId;
  final String peerDisplayName;
  final DateTime connectedAt;

  static UserConnection? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final peerRaw = (data['peerId'] as String?)?.trim();
    final peer = (peerRaw != null && peerRaw.isNotEmpty) ? peerRaw : doc.id.trim();
    if (peer.isEmpty) return null;
    final name = (data['peerDisplayName'] as String?)?.trim();
    return UserConnection(
      peerId: peer,
      peerDisplayName: (name != null && name.isNotEmpty) ? name : 'Neighbor',
      connectedAt: (data['connectedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
