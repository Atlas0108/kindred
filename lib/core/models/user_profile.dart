import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.homeGeoPoint,
    this.discoveryRadiusMiles = 25,
    this.karma = 0,
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final GeoPoint? homeGeoPoint;
  final int discoveryRadiusMiles;
  final int karma;
  final DateTime? createdAt;

  static UserProfile fromDoc(String uid, Map<String, dynamic> data) {
    final home = data['homeGeoPoint'];
    return UserProfile(
      uid: uid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? data['displayName'] as String
          : 'Neighbor',
      photoUrl: data['photoUrl'] as String?,
      homeGeoPoint: home is GeoPoint ? home : null,
      discoveryRadiusMiles: (data['discoveryRadiusMiles'] as num?)?.toInt().clamp(10, 100) ?? 25,
      karma: (data['karma'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toWriteMap() {
    return {
      'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (homeGeoPoint != null) 'homeGeoPoint': homeGeoPoint,
      'discoveryRadiusMiles': discoveryRadiusMiles.clamp(10, 100),
      'karma': karma,
    };
  }
}
