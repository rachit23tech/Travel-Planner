import 'dart:convert';

import '../models/place.dart';
import 'network_client.dart';

/// Talks to Photon (https://photon.komoot.io), a free OpenStreetMap-based
/// geocoder, to turn place names into coordinates (search) and coordinates
/// into place names (reverse).
///
/// Originally this used Nominatim directly, but Nominatim's shared public
/// demo server started returning HTTP 403 for this app's traffic (it
/// aggressively rate-limits/blocks by network). Photon is a different host
/// built on the same OSM data and doesn't require an API key, but it's
/// still someone else's free public service - self-host Photon or switch
/// to a paid provider (LocationIQ, Geoapify, MapTiler, etc.) before
/// shipping this to real users.
class GeocodingService {
  static const _searchUrl = 'https://photon.komoot.io/api/';
  static const _reverseUrl = 'https://photon.komoot.io/reverse';
  static const _userAgent = 'TravelPlannerApp/1.0 (contact@example.com)';

  Future<List<Place>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'q': trimmed,
      'limit': '6',
      'lang': 'en',
    });

    final response = await getWithRetry(uri, headers: {'User-Agent': _userAgent});
    _checkStatus(response.statusCode);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final features = decoded['features'] as List<dynamic>? ?? [];
    return features
        .map((f) => Place.fromPhotonFeature(f as Map<String, dynamic>))
        .toList();
  }

  Future<Place> reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse(_reverseUrl).replace(queryParameters: {
      'lon': lon.toString(),
      'lat': lat.toString(),
      'lang': 'en',
    });

    final response = await getWithRetry(uri, headers: {'User-Agent': _userAgent});
    _checkStatus(response.statusCode);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final features = decoded['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) {
      return Place(displayName: 'My Location', lat: lat, lon: lon);
    }

    final parsed = Place.fromPhotonFeature(features.first as Map<String, dynamic>);
    // Keep the device's own GPS coordinates rather than Photon's (usually
    // identical, but the device reading is the source of truth here).
    return Place(displayName: parsed.displayName, lat: lat, lon: lon);
  }

  void _checkStatus(int statusCode) {
    if (statusCode == 403) {
      throw Exception(
        'Geocoding blocked (HTTP 403) by the search server. It may be '
        'rate-limiting this network - try again shortly.',
      );
    }
    if (statusCode != 200) {
      throw Exception('Request failed (HTTP $statusCode).');
    }
  }
}
