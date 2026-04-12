import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_geohash/dart_geohash.dart';

/// Geohash precision ~5 gives ~4.9km cells; stored for future indexed queries.
const int kGeohashPrecision = 5;

final GeoHasher _geoHasher = GeoHasher();

String encodeGeohash(double lat, double lng) {
  return _geoHasher.encode(lng, lat, precision: kGeohashPrecision);
}

double haversineMiles(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earthRadiusMiles = 3958.8;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMiles * c;
}

double _rad(double deg) => deg * math.pi / 180;

double distanceToGeoPointMiles(GeoPoint from, GeoPoint to) {
  return haversineMiles(from.latitude, from.longitude, to.latitude, to.longitude);
}

bool withinRadiusMiles(GeoPoint center, GeoPoint target, double radiusMiles) {
  return distanceToGeoPointMiles(center, target) <= radiusMiles;
}
