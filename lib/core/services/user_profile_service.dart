import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../kindred_trace.dart';
import '../models/user_profile.dart';

class UserProfileService {
  UserProfileService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const Duration _profileCacheTtl = Duration(seconds: 45);
  static const Duration _fetchTimeout = Duration(seconds: 12);
  static const Duration _ensureProfileTimeout = Duration(seconds: 12);

  String? _cacheUid;
  UserProfile? _cachedProfile;
  DateTime? _cachedAt;
  Future<UserProfile?>? _inFlightFetch;
  String? _inFlightUid;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection('users').doc(uid);

  /// Clears [fetchProfile] memory cache (call after writes).
  void invalidateProfileCache() {
    _cacheUid = null;
    _cachedProfile = null;
    _cachedAt = null;
  }

  Stream<UserProfile?> profileStream(String uid) {
    return _userRef(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserProfile.fromDoc(uid, doc.data()!);
    });
  }

  /// Loads `users/{uid}` from Firestore with a short-lived memory cache and in-flight dedupe.
  Future<UserProfile?> fetchProfile(String uid) async {
    kindredTrace('UserProfileService.fetchProfile enter', uid);
    final now = DateTime.now();
    if (_cacheUid == uid && _cachedAt != null) {
      if (now.difference(_cachedAt!) < _profileCacheTtl) {
        kindredTrace('UserProfileService.fetchProfile cache hit', uid);
        return _cachedProfile;
      }
    }

    if (_inFlightFetch != null && _inFlightUid == uid) {
      kindredTrace('UserProfileService.fetchProfile awaiting in-flight', uid);
      return _inFlightFetch!;
    }

    _inFlightUid = uid;
    _inFlightFetch = _fetchProfileFromServer(uid).whenComplete(() {
      _inFlightFetch = null;
      _inFlightUid = null;
      kindredTrace('UserProfileService.fetchProfile in-flight complete', uid);
    });

    return _inFlightFetch!;
  }

  Future<UserProfile?> _fetchProfileFromServer(String uid) async {
    kindredTrace('UserProfileService._fetchProfileFromServer before users/$uid .get()');
    try {
      final doc = await _userRef(uid).get().timeout(_fetchTimeout);
      kindredTrace('UserProfileService._fetchProfileFromServer after .get()', 'exists=${doc.exists}');
      final UserProfile? profile;
      if (!doc.exists || doc.data() == null) {
        profile = null;
      } else {
        profile = UserProfile.fromDoc(uid, doc.data()!);
      }
      _cacheUid = uid;
      _cachedProfile = profile;
      _cachedAt = DateTime.now();
      return profile;
    } on TimeoutException {
      kindredTrace(
        'UserProfileService users/$uid .get() timed out',
        'offline or slow; keeping in-memory cache if any',
      );
      if (_cacheUid == uid) {
        return _cachedProfile;
      }
      return null;
    }
  }

  /// Creates `users/{uid}` if it does not exist. Called after sign-in; errors are ignored.
  Future<void> ensureProfile({required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) {
      kindredTrace('UserProfileService.ensureProfile skip (no user)');
      return;
    }
    kindredTrace('UserProfileService.ensureProfile start', user.uid);
    final ref = _userRef(user.uid);
    kindredTrace('UserProfileService.ensureProfile before .get() users/${user.uid}');
    try {
      final snap = await ref.get().timeout(_ensureProfileTimeout);
      kindredTrace('UserProfileService.ensureProfile after .get()', 'exists=${snap.exists}');
      if (snap.exists) {
        kindredTrace('UserProfileService.ensureProfile done (doc already exists)');
        return;
      }
    } on TimeoutException {
      kindredTrace('UserProfileService.ensureProfile .get() timed out', user.uid);
      return;
    }
    kindredTrace('UserProfileService.ensureProfile before .set() create user doc');
    try {
      await ref.set({
        'displayName': displayName,
        'discoveryRadiusMiles': 25,
        'karma': 0,
        'createdAt': Timestamp.fromDate(DateTime.now().toUtc()),
      }).timeout(_ensureProfileTimeout);
    } on TimeoutException {
      kindredTrace('UserProfileService.ensureProfile .set() timed out', user.uid);
      return;
    }
    kindredTrace('UserProfileService.ensureProfile after .set()');
    invalidateProfileCache();
  }

  Future<void> updateHomeAndRadius({
    required GeoPoint homeGeoPoint,
    required int discoveryRadiusMiles,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await _userRef(user.uid).set({
      'homeGeoPoint': homeGeoPoint,
      'discoveryRadiusMiles': discoveryRadiusMiles.clamp(10, 100),
    }, SetOptions(merge: true));
    invalidateProfileCache();
  }

  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await _userRef(
      user.uid,
    ).set({'displayName': name.trim().isEmpty ? 'Neighbor' : name.trim()}, SetOptions(merge: true));
    invalidateProfileCache();
  }
}
