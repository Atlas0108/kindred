import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_account_type.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.accountType = UserAccountType.personal,
    this.firstName,
    this.lastName,
    this.organizationName,
    this.businessName,
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
    this.eventsAttended = 0,
    this.requestsFulfilled = 0,
    this.eventsProgressNote,
    this.requestsProgressNote,
    this.staffEmails = const [],
  });

  final String uid;
  final String displayName;
  final UserAccountType accountType;
  final String? firstName;
  final String? lastName;
  /// Nonprofit accounts: public name (replaces first + last in UI).
  final String? organizationName;
  /// Business accounts: public name (replaces first + last in UI).
  final String? businessName;
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
  final int eventsAttended;
  final int requestsFulfilled;
  final String? eventsProgressNote;
  final String? requestsProgressNote;
  /// Lowercase emails allowed to use this org/business account (nonprofit & business only).
  final List<String> staffEmails;

  /// Shown in UI when [accountEmail] is the signed-in user’s email (hides legacy `displayName == email`).
  static String displayNameForUi(String storedName, {String? accountEmail}) {
    final d = storedName.trim();
    if (d.isEmpty) return 'Neighbor';
    final em = accountEmail?.trim();
    if (em != null && em.isNotEmpty && d == em) return 'Neighbor';
    return d;
  }

  /// Public-facing name: org/business name, or "First Last", else legacy [displayName].
  String get publicDisplayLabel {
    if (accountType == UserAccountType.nonprofit) {
      final o = organizationName?.trim() ?? '';
      if (o.isNotEmpty) return o;
    } else if (accountType == UserAccountType.business) {
      final b = businessName?.trim() ?? '';
      if (b.isNotEmpty) return b;
    }
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    final combined = '$f $l'.trim();
    if (combined.isNotEmpty) return combined;
    final d = displayName.trim();
    if (d.isNotEmpty && d != 'Neighbor') return d;
    return 'Neighbor';
  }

  /// Identity + home map pin are required before the rest of the app.
  bool get isProfileSetupComplete {
    if (homeGeoPoint == null) return false;
    switch (accountType) {
      case UserAccountType.personal:
        final f = firstName?.trim() ?? '';
        final l = lastName?.trim() ?? '';
        return f.isNotEmpty && l.isNotEmpty;
      case UserAccountType.nonprofit:
        return (organizationName?.trim() ?? '').isNotEmpty;
      case UserAccountType.business:
        return (businessName?.trim() ?? '').isNotEmpty;
    }
  }

  static UserProfile fromDoc(String uid, Map<String, dynamic> data) {
    final home = data['homeGeoPoint'];
    final rawBio = (data['bio'] as String?)?.trim();
    final fn = (data['firstName'] as String?)?.trim();
    final ln = (data['lastName'] as String?)?.trim();
    final org = (data['organizationName'] as String?)?.trim();
    final biz = (data['businessName'] as String?)?.trim();
    final staffRaw = data['staffEmails'];
    final staffList = <String>[];
    if (staffRaw is List) {
      for (final e in staffRaw) {
        final s = e?.toString().trim().toLowerCase() ?? '';
        if (s.contains('@')) staffList.add(s);
      }
    }
    return UserProfile(
      uid: uid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : 'Neighbor',
      accountType: UserAccountType.fromFirestore(data['accountType']),
      firstName: fn != null && fn.isNotEmpty ? fn : null,
      lastName: ln != null && ln.isNotEmpty ? ln : null,
      organizationName: org != null && org.isNotEmpty ? org : null,
      businessName: biz != null && biz.isNotEmpty ? biz : null,
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
      eventsAttended: (data['eventsAttended'] as num?)?.toInt().clamp(0, 9999) ?? 0,
      requestsFulfilled: (data['requestsFulfilled'] as num?)?.toInt().clamp(0, 9999) ?? 0,
      eventsProgressNote: (data['eventsProgressNote'] as String?)?.trim(),
      requestsProgressNote: (data['requestsProgressNote'] as String?)?.trim(),
      staffEmails: staffList,
    );
  }

  Map<String, dynamic> toWriteMap() {
    return {
      'displayName': displayName,
      'accountType': accountType.firestoreValue,
      if (firstName != null && firstName!.trim().isNotEmpty) 'firstName': firstName!.trim(),
      if (lastName != null && lastName!.trim().isNotEmpty) 'lastName': lastName!.trim(),
      if (organizationName != null && organizationName!.trim().isNotEmpty)
        'organizationName': organizationName!.trim(),
      if (businessName != null && businessName!.trim().isNotEmpty)
        'businessName': businessName!.trim(),
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
