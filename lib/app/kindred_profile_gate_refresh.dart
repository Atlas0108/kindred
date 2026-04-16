import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/kindred_trace.dart';
import '../core/models/user_profile.dart';

/// Drives [GoRouter] redirects from auth + `users/{uid}` so incomplete profiles go to setup.
class KindredProfileGateRefresh extends ChangeNotifier {
  KindredProfileGateRefresh(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  /// `null` until the first Firestore snapshot after sign-in (router uses `/session-loading` until known).
  bool? _setupComplete;
  bool? get setupComplete => _setupComplete;

  void attach() {
    _authSub?.cancel();
    _authSub = _auth.authStateChanges().listen(_onAuthUser);
    _onAuthUser(_auth.currentUser);
  }

  void _onAuthUser(User? user) {
    _profileSub?.cancel();
    _profileSub = null;
    if (user == null) {
      _setupComplete = null;
      notifyListeners();
      return;
    }
    _setupComplete = null;
    notifyListeners();
    _profileSub = _firestore.collection('users').doc(user.uid).snapshots().listen(
      _onProfileSnap,
      onError: (Object error, StackTrace stack) {
        // Avoid a permanent /session-loading loop when Firestore listen fails
        // (e.g. rules/config mismatch right after project migration).
        kindredTrace('KindredProfileGateRefresh profile listen error', error);
        _setupComplete = false;
        notifyListeners();
      },
    );
  }

  void _onProfileSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || snap.data() == null) {
      _setupComplete = false;
    } else {
      final p = UserProfile.fromDoc(snap.id, snap.data()!);
      _setupComplete = p.isProfileSetupComplete;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    unawaited(_profileSub?.cancel());
    super.dispose();
  }
}
