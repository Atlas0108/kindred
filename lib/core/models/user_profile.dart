import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.bio,
    this.homeGeoPoint,
    this.homeCityLabel,
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
  final String? photoUrl;
  /// Short about text; shown on profile.
  final String? bio;
  final GeoPoint? homeGeoPoint;
  /// From place search / user (e.g. "Oakland, California"); shown with [homeGeoPoint] for local feeds.
  final String? homeCityLabel;
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
    return UserProfile(
      uid: uid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : 'Neighbor',
      photoUrl: data['photoUrl'] as String?,
      bio: rawBio != null && rawBio.isNotEmpty ? rawBio : null,
      homeGeoPoint: home is GeoPoint ? home : null,
      homeCityLabel: (data['homeCityLabel'] as String?)?.trim().isNotEmpty == true
          ? (data['homeCityLabel'] as String).trim()
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
      if (photoUrl != null && photoUrl!.trim().isNotEmpty) 'photoUrl': photoUrl!.trim(),
      if (bio != null && bio!.trim().isNotEmpty) 'bio': bio!.trim(),
      if (homeGeoPoint != null) 'homeGeoPoint': homeGeoPoint,
      if (homeCityLabel != null && homeCityLabel!.trim().isNotEmpty)
        'homeCityLabel': homeCityLabel!.trim(),
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
}
