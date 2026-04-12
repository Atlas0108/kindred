import 'package:cloud_firestore/cloud_firestore.dart';

/// 1:1 chat metadata in `conversations/{conversationId}`.
class DirectConversation {
  const DirectConversation({
    required this.id,
    required this.participantIds,
    required this.participantNames,
    required this.lastMessageText,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    required this.lastReadAtByUser,
    required this.updatedAt,
    required this.createdAt,
  });

  final String id;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final String lastMessageText;
  final DateTime lastMessageAt;
  /// Uid of the sender of [lastMessageText], if known (set on new sends).
  final String lastMessageSenderId;
  /// Per-participant “read through” time for this thread.
  final Map<String, DateTime> lastReadAtByUser;
  final DateTime updatedAt;
  final DateTime createdAt;

  /// Whether [myUid] has not yet opened the latest message from the other person.
  bool hasUnreadFor(String myUid) {
    if (lastMessageText.trim().isEmpty) return false;
    if (lastMessageSenderId.isEmpty) return false;
    if (lastMessageSenderId == myUid) return false;
    final read = lastReadAtByUser[myUid];
    if (read == null) return true;
    return lastMessageAt.isAfter(read);
  }

  static DirectConversation? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final ids = data['participantIds'];
    if (ids is! List || ids.length != 2) return null;
    final pair = ids.map((e) => e.toString()).toList();
    final rawNames = data['participantNames'];
    final names = <String, String>{};
    if (rawNames is Map) {
      for (final e in rawNames.entries) {
        final k = e.key?.toString();
        final v = e.value?.toString();
        if (k != null && v != null && k.isNotEmpty) names[k] = v;
      }
    }
    final rawRead = data['lastReadAtByUser'];
    final readMap = <String, DateTime>{};
    if (rawRead is Map) {
      for (final e in rawRead.entries) {
        final k = e.key?.toString();
        final ts = e.value;
        if (k != null && k.isNotEmpty && ts is Timestamp) {
          readMap[k] = ts.toDate();
        }
      }
    }
    return DirectConversation(
      id: doc.id,
      participantIds: pair,
      participantNames: names,
      lastMessageText: (data['lastMessageText'] as String?)?.trim() ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastMessageSenderId: (data['lastMessageSenderId'] as String?)?.trim() ?? '',
      lastReadAtByUser: readMap,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String? displayNameForUser(String uid) {
    final n = participantNames[uid]?.trim();
    if (n != null && n.isNotEmpty) return n;
    return null;
  }

  String otherParticipantId(String myUid) {
    return participantIds.firstWhere((id) => id != myUid, orElse: () => participantIds.last);
  }
}
