import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/connection_request.dart';
import '../models/user_connection.dart';

class ConnectionService {
  ConnectionService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) => _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _connectionRequests(String uid) =>
      _userRef(uid).collection('connectionRequests');

  CollectionReference<Map<String, dynamic>> _connections(String uid) =>
      _userRef(uid).collection('connections');

  /// Writes `users/{toUserId}/connectionRequests/{myUid}`.
  Future<void> sendConnectionRequest({
    required String toUserId,
    required String myDisplayName,
  }) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError('Not signed in');
    if (toUserId == me.uid) throw ArgumentError('Cannot request yourself');

    final conn = await _connections(me.uid).doc(toUserId).get();
    if (conn.exists) return;

    final pendingMine = await _connectionRequests(toUserId).doc(me.uid).get();
    if (pendingMine.exists) return;

    final name = myDisplayName.trim().isEmpty ? 'Neighbor' : myDisplayName.trim();
    await _connectionRequests(toUserId).doc(me.uid).set({
      'fromUserId': me.uid,
      'fromDisplayName': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<ConnectionRequest>> incomingRequestsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _connectionRequests(uid).snapshots().map((snap) {
      final list =
          snap.docs.map(ConnectionRequest.fromDoc).whereType<ConnectionRequest>().toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<List<UserConnection>> myConnectionsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _connections(uid).snapshots().map((snap) {
      final list = snap.docs.map(UserConnection.fromDoc).whereType<UserConnection>().toList();
      list.sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
      return list;
    });
  }

  Future<void> approveConnectionRequest({
    required String fromUserId,
    required String fromDisplayName,
    required String myDisplayName,
  }) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError('Not signed in');

    final theirName = fromDisplayName.trim().isEmpty ? 'Neighbor' : fromDisplayName.trim();
    final myName = myDisplayName.trim().isEmpty ? 'Neighbor' : myDisplayName.trim();
    final now = FieldValue.serverTimestamp();

    final batch = _firestore.batch();
    batch.delete(_connectionRequests(me.uid).doc(fromUserId));
    batch.set(_connections(me.uid).doc(fromUserId), {
      'peerId': fromUserId,
      'peerDisplayName': theirName,
      'connectedAt': now,
    });
    batch.set(_connections(fromUserId).doc(me.uid), {
      'peerId': me.uid,
      'peerDisplayName': myName,
      'connectedAt': now,
    });
    await batch.commit();
  }

  Future<void> declineConnectionRequest(String fromUserId) async {
    final me = _auth.currentUser;
    if (me == null) throw StateError('Not signed in');
    await _connectionRequests(me.uid).doc(fromUserId).delete();
  }
}
