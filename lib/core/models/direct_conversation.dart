import 'package:cloud_firestore/cloud_firestore.dart';

/// 1:1 chat metadata in `conversations/{conversationId}`.
class DirectConversation {
  const DirectConversation({
    required this.id,
    required this.participantIds,
    required this.participantNames,
    required this.lastMessageText,
    required this.lastMessageAt,
    required this.updatedAt,
    required this.createdAt,
  });

  final String id;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final String lastMessageText;
  final DateTime lastMessageAt;
  final DateTime updatedAt;
  final DateTime createdAt;

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
    return DirectConversation(
      id: doc.id,
      participantIds: pair,
      participantNames: names,
      lastMessageText: (data['lastMessageText'] as String?)?.trim() ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
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
