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

  /// Auth-backed label for `ensureProfile` / connections — uses [User.displayName] only, never email.
  static String preferredDisplayNameFromAuthUser(User user) {
    final d = user.displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    return 'Neighbor';
  }

  /// Value stored in `users/{uid}.displayName`: empty or the account email becomes [Neighbor].
  static String displayNameForStorage(User user, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Neighbor';
    final em = user.email?.trim();
    if (em != null && em.isNotEmpty && t == em) return 'Neighbor';
    return t;
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
    final storedName = displayNameForStorage(user, displayName);
    try {
      await ref.set({
        'displayName': storedName,
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
    String? homeCityLabel,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final data = <String, dynamic>{
      'homeGeoPoint': homeGeoPoint,
      'discoveryRadiusMiles': discoveryRadiusMiles.clamp(10, 100),
    };
    final label = homeCityLabel?.trim();
    if (label != null && label.isNotEmpty) {
      data['homeCityLabel'] = label;
    } else {
      data['homeCityLabel'] = FieldValue.delete();
    }
    await _userRef(user.uid).set(data, SetOptions(merge: true));
    invalidateProfileCache();
  }

  /// Home tab browse center (independent of [updateHomeAndRadius]). Uses [discoveryRadiusMiles] for distance.
  Future<void> updateFeedBrowseLocation({
    required GeoPoint feedFilterGeoPoint,
    required String feedFilterCityLabel,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final label = feedFilterCityLabel.trim();
    await _userRef(user.uid).set(
      {
        'feedFilterGeoPoint': feedFilterGeoPoint,
        if (label.isNotEmpty) 'feedFilterCityLabel': label else 'feedFilterCityLabel': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
    invalidateProfileCache();
  }

  /// Clears feed browse override so Home uses [homeGeoPoint] again.
  Future<void> clearFeedBrowseLocation() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await _userRef(user.uid).set(
      {
        'feedFilterGeoPoint': FieldValue.delete(),
        'feedFilterCityLabel': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
    invalidateProfileCache();
  }

  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await _userRef(user.uid).set(
      {'displayName': displayNameForStorage(user, name)},
      SetOptions(merge: true),
    );
    invalidateProfileCache();
  }

  static const int maxBioLength = 500;

  /// Saves first/last name and optional bio during profile setup (home is set via [updateHomeAndRadius]).
  Future<void> updateProfileNamesAndOptionalBio({
    required String firstName,
    required String lastName,
    String? bio,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty || l.isEmpty) {
      throw ArgumentError('First and last name are required.');
    }
    final combined = '$f $l'.trim();
    final data = <String, dynamic>{
      'firstName': f,
      'lastName': l,
      'displayName': displayNameForStorage(user, combined),
    };
    final bioTrim = bio?.trim();
    if (bioTrim != null && bioTrim.isNotEmpty) {
      data['bio'] = bioTrim.length > maxBioLength ? bioTrim.substring(0, maxBioLength) : bioTrim;
    }
    await _userRef(user.uid).set(data, SetOptions(merge: true));
    try {
      await user.updateDisplayName(combined);
    } on Object catch (_) {}
    invalidateProfileCache();
  }

  /// Updates the signed-in user’s public profile fields (merge). Empty strings clear optional fields.
  Future<void> updatePublicProfile({
    required String firstName,
    required String lastName,
    required String? photoUrl,
    required String? bio,
    required String? neighborhoodLabel,
    required int eventsAttended,
    required int requestsFulfilled,
    required String? eventsProgressNote,
    required String? requestsProgressNote,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    final f = firstName.trim();
    final l = lastName.trim();
    final combined = '$f $l'.trim();

    final data = <String, dynamic>{
      'firstName': f,
      'lastName': l,
      'displayName': displayNameForStorage(user, combined.isEmpty ? 'Neighbor' : combined),
      'profileTags': FieldValue.delete(),
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

    final bioTrim = bio?.trim();
    if (bioTrim == null || bioTrim.isEmpty) {
      data['bio'] = FieldValue.delete();
    } else {
      data['bio'] = bioTrim.length > maxBioLength ? bioTrim.substring(0, maxBioLength) : bioTrim;
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
