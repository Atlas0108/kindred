import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../kindred_trace.dart';

/// One row from a geocode search, suitable for storing [geoPoint] + [label] together on the profile.
class GeoSearchResult {
  const GeoSearchResult({required this.label, required this.geoPoint});

  /// Stable display string for Firestore (e.g. "Berkeley, California").
  final String label;
  final GeoPoint geoPoint;
}

/// City / place search using [Photon](https://photon.komoot.io/) (OpenStreetMap-backed, CORS-friendly for Flutter Web).
class LocationSearchService {
  LocationSearchService._();

  static const _userAgent = 'KindredApp/1.0 (local community app)';
  static const _timeout = Duration(seconds: 10);

  static String _labelFromPhotonProps(Map<String, dynamic> props) {
    final name = (props['name'] as String?)?.trim();
    final city = (props['city'] as String?)?.trim();
    final state = (props['state'] as String?)?.trim();
    final country = (props['country'] as String?)?.trim();

    if (name != null && name.isNotEmpty && state != null && state.isNotEmpty) {
      return '$name, $state';
    }
    if (city != null && city.isNotEmpty && state != null && state.isNotEmpty) {
      return '$city, $state';
    }
    if (name != null && name.isNotEmpty && country != null && country.isNotEmpty) {
      return '$name, $country';
    }
    if (city != null && city.isNotEmpty && country != null && country.isNotEmpty) {
      return '$city, $country';
    }
    if (name != null && name.isNotEmpty) return name;
    if (city != null && city.isNotEmpty) return city;
    return 'Unknown place';
  }

  static Future<List<GeoSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': q,
      'limit': '8',
    });

    try {
      final resp = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': _userAgent,
            },
          )
          .timeout(_timeout);

      if (resp.statusCode != 200) {
        kindredTrace('LocationSearchService.search', 'HTTP ${resp.statusCode}');
        return [];
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return [];
      final features = decoded['features'];
      if (features is! List) return [];

      final out = <GeoSearchResult>[];
      for (final raw in features) {
        if (raw is! Map<String, dynamic>) continue;
        final geom = raw['geometry'];
        if (geom is! Map<String, dynamic>) continue;
        final coords = geom['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        final lon = (coords[0] is num) ? (coords[0] as num).toDouble() : double.tryParse('${coords[0]}');
        final lat = (coords[1] is num) ? (coords[1] as num).toDouble() : double.tryParse('${coords[1]}');
        if (lat == null || lon == null) continue;
        final props = raw['properties'];
        if (props is! Map<String, dynamic>) continue;
        final label = _labelFromPhotonProps(props);
        if (label.isEmpty || label == 'Unknown place') continue;
        out.add(GeoSearchResult(label: label, geoPoint: GeoPoint(lat, lon)));
      }
      return out;
    } on Object catch (e) {
      kindredTrace('LocationSearchService.search error', e);
      return [];
    }
  }
}
