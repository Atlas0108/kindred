import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_message.dart';
import '../models/direct_conversation.dart';

class MessagingService {
  MessagingService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  /// Deterministic doc id for a pair of user ids.
  static String conversationIdForPair(String uidA, String uidB) {
    if (uidA.compareTo(uidB) < 0) return '${uidA}_$uidB';
    return '${uidB}_$uidA';
  }

  static bool _docHasPair(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String myUid,
    String otherUid,
  ) {
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null) return false;
    final raw = data['participantIds'];
    if (raw is! List || raw.length != 2) return false;
    final a = raw[0].toString();
    final b = raw[1].toString();
    return (a == myUid || b == myUid) && (a == otherUid || b == otherUid);
  }

  /// Creates the conversation document if missing, then returns its id.
  Future<String> ensureDirectConversation({
    required String otherUserId,
    required String otherDisplayName,
    required String myDisplayName,
  }) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError('Not signed in');
    if (otherUserId.isEmpty || otherUserId == me.uid) {
      throw ArgumentError('Invalid other user');
    }

    final id = conversationIdForPair(me.uid, otherUserId);
    final ref = _conversations.doc(id);
    final ids = [me.uid, otherUserId]..sort();

    // Server read avoids stale local cache (wrong exists flag → wrong write path / rules mismatch).
    DocumentSnapshot<Map<String, dynamic>> existing;
    try {
      existing = await ref.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      throw FirebaseException(
        plugin: e.plugin,
        message: 'load conversation $id: ${e.message}',
        code: e.code,
      );
    }
    if (!existing.exists || !_docHasPair(existing, me.uid, otherUserId)) {
      final now = FieldValue.serverTimestamp();
      try {
        // merge: true repairs partial/corrupt docs; create still works when missing.
        await ref.set(
          {
            'participantIds': ids,
            'participantNames': {
              me.uid: myDisplayName.trim().isEmpty ? 'Neighbor' : myDisplayName.trim(),
              otherUserId: otherDisplayName.trim().isEmpty ? 'Neighbor' : otherDisplayName.trim(),
            },
            'lastMessageText': '',
            'lastMessageAt': now,
            'updatedAt': now,
            'createdAt': now,
          },
          SetOptions(merge: true),
        );
      } on FirebaseException catch (e) {
        throw FirebaseException(
          plugin: e.plugin,
          message: 'create conversation $id: ${e.message}',
          code: e.code,
        );
      }
    }

    return id;
  }

  Stream<List<DirectConversation>> myConversationsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    // Sort client-side so we only need `array-contains` (auto-indexed). Combining
    // `array-contains` + `orderBy(updatedAt)` requires a composite index and causes
    // cache-first snapshots to show data briefly, then fail when the server responds.
    return _conversations
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .map((snap) {
          final list =
              snap.docs.map(DirectConversation.fromDoc).whereType<DirectConversation>().toList();
          list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return list;
        });
  }

  Stream<DirectConversation?> conversationStream(String conversationId) {
    return _conversations.doc(conversationId).snapshots().map(DirectConversation.fromDoc);
  }

  Stream<List<ChatMessage>> messagesStream(String conversationId) {
    return _conversations
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs.map(ChatMessage.fromDoc).whereType<ChatMessage>().toList(),
        );
  }

  Future<void> sendMessage(String conversationId, String text) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError('Not signed in');
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final convRef = _conversations.doc(conversationId);
    final msgRef = convRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    final batch = _firestore.batch();
    batch.set(msgRef, {
      'senderId': me.uid,
      'text': trimmed,
      'createdAt': now,
    });
    batch.update(convRef, {
      'lastMessageText': trimmed,
      'lastMessageAt': now,
      'updatedAt': now,
    });
    await batch.commit();
  }
}
