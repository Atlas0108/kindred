import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../kindred_trace.dart';
import '../models/user_profile.dart';
import '../utils/cover_image_prepare.dart';

class UserProfileService {
  UserProfileService(this._firestore, this._auth, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  static const Duration _storagePutTimeout = Duration(seconds: 180);
  static const Duration _storageUrlTimeout = Duration(seconds: 45);

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

  /// Display name for new/merged `users/{uid}` docs: Auth profile name, else email, else a neutral label.
  static String preferredDisplayNameFromAuthUser(User user) {
    for (final s in [user.displayName?.trim(), user.email?.trim()]) {
      if (s != null && s.isNotEmpty) return s;
    }
    return 'Neighbor';
  }

  Future<String> _awaitUploadTask(UploadTask task, Reference ref) async {
    try {
      await task.timeout(
        _storagePutTimeout,
        onTimeout: () async {
          try {
            await task.cancel();
          } on Object catch (_) {}
          throw TimeoutException(
            'Profile photo upload timed out after ${_storagePutTimeout.inSeconds}s.',
          );
        },
      );
    } on FirebaseException catch (e) {
      kindredTrace('UserProfileService._awaitUploadTask', '${e.code} ${e.message}');
      rethrow;
    }
    return ref.getDownloadURL().timeout(
      _storageUrlTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload finished but timed out fetching the download URL.',
      ),
    );
  }

  /// Picks up gallery bytes or a web [Blob] (same pattern as post covers), uploads, sets [photoUrl].
  Future<void> uploadAndSetProfilePhoto({
    Uint8List? imageBytes,
    Object? webImageBlob,
    String? imageContentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await user.getIdToken(true);

    final mime = (imageContentType ?? '').trim().isEmpty ? 'image/jpeg' : imageContentType!.trim();
    final id = _uuid.v4();

    if (webImageBlob != null) {
      kindredTrace('UserProfileService.uploadAndSetProfilePhoto putBlob (web)', user.uid);
      final ext = mime.toLowerCase().contains('png') ? 'png' : 'jpg';
      final ref = _storage.ref('post_images/${user.uid}/profile_$id.$ext');
      final task = ref.putBlob(
        webImageBlob,
        SettableMetadata(contentType: mime),
      );
      final url = await _awaitUploadTask(task, ref);
      await _userRef(user.uid).set({'photoUrl': url}, SetOptions(merge: true));
      invalidateProfileCache();
      return;
    }

    if (imageBytes == null || imageBytes.isEmpty) {
      throw ArgumentError('image bytes or web blob required');
    }

    final prepared = await prepareCoverImageForUploadAsync(imageBytes, mime);
    kindredTrace(
      'UserProfileService.uploadAndSetProfilePhoto prepared',
      '${prepared.bytes.length} bytes',
    );
    final ext = prepared.contentType.toLowerCase().contains('png') ? 'png' : 'jpg';
    final ref = _storage.ref('post_images/${user.uid}/profile_$id.$ext');
    final task = ref.putData(
      prepared.bytes,
      SettableMetadata(contentType: prepared.contentType),
    );
    final url = await _awaitUploadTask(task, ref);
    await _userRef(user.uid).set({'photoUrl': url}, SetOptions(merge: true));
    invalidateProfileCache();
  }

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
  /// Skips creation when the account has no email (Kindred treats email + display name as the minimum public identity).
  Future<void> ensureProfile({required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) {
      kindredTrace('UserProfileService.ensureProfile skip (no user)');
      return;
    }
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      kindredTrace('UserProfileService.ensureProfile skip (no email on account)');
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

  /// Updates the signed-in user’s public profile fields (merge). Empty strings clear optional fields.
  Future<void> updatePublicProfile({
    required String displayName,
    required String? photoUrl,
    required String? neighborhoodLabel,
    required List<String> profileTags,
    required int eventsAttended,
    required int requestsFulfilled,
    required String? eventsProgressNote,
    required String? requestsProgressNote,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    final tags = <String>[];
    final seen = <String>{};
    for (final t in profileTags) {
      final s = t.trim();
      if (s.isEmpty || seen.contains(s)) continue;
      seen.add(s);
      tags.add(s);
      if (tags.length >= 3) break;
    }

    final data = <String, dynamic>{
      'displayName': displayName.trim().isEmpty ? 'Neighbor' : displayName.trim(),
      'profileTags': tags,
      'eventsAttended': eventsAttended.clamp(0, 9999),
      'requestsFulfilled': requestsFulfilled.clamp(0, 9999),
    };

    final pu = photoUrl?.trim();
    if (pu == null || pu.isEmpty) {
      data['photoUrl'] = FieldValue.delete();
    } else {
      data['photoUrl'] = pu;
    }

    final nb = neighborhoodLabel?.trim();
    if (nb == null || nb.isEmpty) {
      data['neighborhoodLabel'] = FieldValue.delete();
    } else {
      data['neighborhoodLabel'] = nb;
    }

    final en = eventsProgressNote?.trim();
    if (en == null || en.isEmpty) {
      data['eventsProgressNote'] = FieldValue.delete();
    } else {
      data['eventsProgressNote'] = en;
    }

    final rn = requestsProgressNote?.trim();
    if (rn == null || rn.isEmpty) {
      data['requestsProgressNote'] = FieldValue.delete();
    } else {
      data['requestsProgressNote'] = rn;
    }

    await _userRef(user.uid).set(data, SetOptions(merge: true));
    invalidateProfileCache();
  }
}
