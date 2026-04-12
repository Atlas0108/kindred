import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.firstName,
    this.lastName,
    this.photoUrl,
    this.bio,
    this.homeGeoPoint,
    this.homeCityLabel,
    this.feedFilterGeoPoint,
    this.feedFilterCityLabel,
    this.discoveryRadiusMiles = 25,
    this.karma = 0,
    this.createdAt,
    this.neighborhoodLabel,
    this.profileTags = const [],
    this.eventsAttended = 0,
    this.requestsFulfilled = 0,
    this.eventsProgressNote,
    this.requestsProgressNote,
  });

  final String uid;
  final String displayName;
  final String? firstName;
  final String? lastName;
  final String? photoUrl;
  /// Short about text; shown on profile.
  final String? bio;
  final GeoPoint? homeGeoPoint;
  /// From place search / user (e.g. "Oakland, California"); shown with [homeGeoPoint] for local feeds.
  final String? homeCityLabel;
  /// Optional center for Home tab browse; when null, [homeGeoPoint] is used.
  final GeoPoint? feedFilterGeoPoint;
  final String? feedFilterCityLabel;
  final int discoveryRadiusMiles;
  final int karma;
  final DateTime? createdAt;

  /// Shown as “{label} • Since {year}” on the profile header.
  final String? neighborhoodLabel;
  final List<String> profileTags;
  final int eventsAttended;
  final int requestsFulfilled;
  final String? eventsProgressNote;
  final String? requestsProgressNote;

  /// Shown in UI when [accountEmail] is the signed-in user’s email (hides legacy `displayName == email`).
  static String displayNameForUi(String storedName, {String? accountEmail}) {
    final d = storedName.trim();
    if (d.isEmpty) return 'Neighbor';
    final em = accountEmail?.trim();
    if (em != null && em.isNotEmpty && d == em) return 'Neighbor';
    return d;
  }

  /// Public-facing name: "First Last" when set, else legacy [displayName] (if not placeholder).
  String get publicDisplayLabel {
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    final combined = '$f $l'.trim();
    if (combined.isNotEmpty) return combined;
    final d = displayName.trim();
    if (d.isNotEmpty && d != 'Neighbor') return d;
    return 'Neighbor';
  }

  /// First name, last name, and home map pin are required before the rest of the app.
  bool get isProfileSetupComplete {
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    return f.isNotEmpty && l.isNotEmpty && homeGeoPoint != null;
  }

  static UserProfile fromDoc(String uid, Map<String, dynamic> data) {
    final home = data['homeGeoPoint'];
    final rawTags = data['profileTags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is String && t.trim().isNotEmpty) tags.add(t.trim());
      }
    }
    final rawBio = (data['bio'] as String?)?.trim();
    final fn = (data['firstName'] as String?)?.trim();
    final ln = (data['lastName'] as String?)?.trim();
    return UserProfile(
      uid: uid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : 'Neighbor',
      firstName: fn != null && fn.isNotEmpty ? fn : null,
      lastName: ln != null && ln.isNotEmpty ? ln : null,
      photoUrl: data['photoUrl'] as String?,
      bio: rawBio != null && rawBio.isNotEmpty ? rawBio : null,
      homeGeoPoint: home is GeoPoint ? home : null,
      homeCityLabel: (data['homeCityLabel'] as String?)?.trim().isNotEmpty == true
          ? (data['homeCityLabel'] as String).trim()
          : null,
      feedFilterGeoPoint: data['feedFilterGeoPoint'] is GeoPoint ? data['feedFilterGeoPoint'] as GeoPoint : null,
      feedFilterCityLabel: (data['feedFilterCityLabel'] as String?)?.trim().isNotEmpty == true
          ? (data['feedFilterCityLabel'] as String).trim()
          : null,
      discoveryRadiusMiles: (data['discoveryRadiusMiles'] as num?)?.toInt().clamp(10, 100) ?? 25,
      karma: (data['karma'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      neighborhoodLabel: (data['neighborhoodLabel'] as String?)?.trim(),
      profileTags: tags,
      eventsAttended: (data['eventsAttended'] as num?)?.toInt().clamp(0, 9999) ?? 0,
      requestsFulfilled: (data['requestsFulfilled'] as num?)?.toInt().clamp(0, 9999) ?? 0,
      eventsProgressNote: (data['eventsProgressNote'] as String?)?.trim(),
      requestsProgressNote: (data['requestsProgressNote'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toWriteMap() {
    return {
      'displayName': displayName,
      if (firstName != null && firstName!.trim().isNotEmpty) 'firstName': firstName!.trim(),
      if (lastName != null && lastName!.trim().isNotEmpty) 'lastName': lastName!.trim(),
      if (photoUrl != null && photoUrl!.trim().isNotEmpty) 'photoUrl': photoUrl!.trim(),
      if (bio != null && bio!.trim().isNotEmpty) 'bio': bio!.trim(),
      if (homeGeoPoint != null) 'homeGeoPoint': homeGeoPoint,
      if (homeCityLabel != null && homeCityLabel!.trim().isNotEmpty)
        'homeCityLabel': homeCityLabel!.trim(),
      if (feedFilterGeoPoint != null) 'feedFilterGeoPoint': feedFilterGeoPoint,
      if (feedFilterCityLabel != null && feedFilterCityLabel!.trim().isNotEmpty)
        'feedFilterCityLabel': feedFilterCityLabel!.trim(),
      'discoveryRadiusMiles': discoveryRadiusMiles.clamp(10, 100),
      'karma': karma,
      if (neighborhoodLabel != null && neighborhoodLabel!.trim().isNotEmpty)
        'neighborhoodLabel': neighborhoodLabel!.trim(),
      'profileTags': profileTags,
      'eventsAttended': eventsAttended.clamp(0, 9999),
      'requestsFulfilled': requestsFulfilled.clamp(0, 9999),
      if (eventsProgressNote != null && eventsProgressNote!.trim().isNotEmpty)
        'eventsProgressNote': eventsProgressNote!.trim(),
      if (requestsProgressNote != null && requestsProgressNote!.trim().isNotEmpty)
        'requestsProgressNote': requestsProgressNote!.trim(),
    };
  }

  /// Center for Home tab geo filter; [fallback] when neither feed override nor home is set.
  GeoPoint feedBrowseCenter(GeoPoint fallback) =>
      feedFilterGeoPoint ?? homeGeoPoint ?? fallback;

  /// True when Home uses a browse location different from stored [homeGeoPoint] resolution.
  bool get feedBrowseUsesCustomFilter => feedFilterGeoPoint != null;

  /// Short label for the Home location chip.
  String feedBrowseLabel(GeoPoint fallback) {
    if (feedFilterGeoPoint != null) {
      final l = feedFilterCityLabel?.trim();
      if (l != null && l.isNotEmpty) return l;
      return 'Selected area';
    }
    if (homeGeoPoint != null) {
      final h = homeCityLabel?.trim();
      if (h != null && h.isNotEmpty) return h;
      return 'Home';
    }
    return 'San Francisco area';
  }
}
