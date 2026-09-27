import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';
import '../utils/navigation_geometry.dart';

/// Finds food stops, restrooms, fuel, ATMs/banks, and pharmacies.
///
/// Two providers, split by category:
///  - Geoapify Places (reliable, paid-grade infra, generous free tier)
///    handles food, fuel, ATM/bank and pharmacy - see [geoapifyApiKey].
///  - Restrooms have no clean Geoapify category, so they still go
///    through the free public OpenStreetMap Overpass mirrors, raced in
///    parallel (see `_searchOverpass` below).
/// Until a Geoapify key is set, everything falls back to Overpass, same
/// as before.
class PoiService {
  // ---------------------------------------------------------------------
  // Geoapify (https://www.geoapify.com/) - primary provider.
  //
  // Get a free key: geoapify.com -> sign up -> My Projects -> the
  // default project already has one -> copy it here. Free tier is
  // 3000 requests/day, no card required. Until this is filled in, every
  // category falls back to the Overpass mirrors below (flaky under
  // load, which is the "server took too long to respond" you've been
  // seeing).
  // ---------------------------------------------------------------------
  static const String geoapifyApiKey = '';

  static const _geoapifyCategoryTags = {
    'food': ['catering.restaurant', 'catering.cafe', 'catering.fast_food'],
    'fuel': ['service.vehicle.fuel'],
    'atm_bank': ['service.financial.atm', 'service.financial.bank'],
    'pharmacy': ['commercial.health_and_beauty.pharmacy'],
  };

  static const _geoapifyTimeout = Duration(seconds: 12);

  static const _categoryAmenityTags = {
    'food': ['restaurant', 'cafe', 'fast_food'],
    'restroom': ['toilets'],
    'fuel': ['fuel'],
    'atm_bank': ['atm', 'bank'],
    'pharmacy': ['pharmacy'],
  };

  static const _maxResults = 20;

  // Fewer sample points along the route keeps each provider's query
  // cheap - each point widens the search corridor and adds real
  // server-side (or, for Geoapify, per-request) cost.
  static const _maxRouteSamplePoints = 15;

  // The Overpass query tells the SERVER to give up after
  // [_overpassQueryTimeoutSeconds]; the client-side HTTP timeout below
  // must be longer than that, or we cut the connection before the
  // server could ever have answered.
  static const _overpassQueryTimeoutSeconds = 20;
  static const _perAttemptTimeout = Duration(seconds: 25);

  /// Public Overpass mirrors, used only for restrooms now. Every mirror
  /// is queried AT THE SAME TIME (see `_searchOverpass` below) and
  /// whichever answers first wins - trying them one after another was
  /// the real bug behind "keeps loading, then times out": with several
  /// mirrors and a 25s timeout each, a user could wait well over a
  /// minute just to find out every one of them was slow. Racing them
  /// removes that multiplication: the worst case is one
  /// [_perAttemptTimeout], not hosts.length * [_perAttemptTimeout].
  ///
  /// These are still free, community-run, unauthenticated servers,
  /// though - they can and do have slow spells with no fix on our end
  /// beyond "try several and hope one is healthy right now", which is
  /// exactly why food/fuel/ATM/pharmacy moved off them entirely.
  static const _overpassHosts = [
    _OverpassHost('overpass-api.de', '/api/interpreter'),
    _OverpassHost('overpass.kumi.systems', '/api/interpreter'),
    _OverpassHost('overpass.openstreetmap.ru', '/api/interpreter'),
    _OverpassHost('maps.mail.ru', '/osm/tools/overpass/api/interpreter'),
    _OverpassHost('overpass.private.coffee', '/api/interpreter'),
  ];

  /// Places near a single point (e.g. the device's current location),
  /// nearest first.
  Future<List<Poi>> searchNear({
    required LatLng center,
    required double radiusMeters,
    required Set<String> categories,
  }) async {
    final raw = await _searchRaw(
      centers: [center],
      radiusMeters: radiusMeters,
      categories: categories,
    );
    final withDistance = raw
        .map((p) => p.withDistance(
              NavigationGeometry.distanceMeters(center, LatLng(p.lat, p.lon)),
            ))
        .toList()
      ..sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
    return withDistance.take(_maxResults).toList();
  }

  /// Places within [corridorRadiusMeters] of the route line itself, so
  /// the results read as "on the way" rather than merely "somewhere
  /// near the trip" - sorted by how close each one is to the route,
  /// not by how far along the route it is.
  Future<List<Poi>> searchAlongRoute({
    required List<LatLng> routePoints,
    required double corridorRadiusMeters,
    required Set<String> categories,
  }) async {
    if (routePoints.isEmpty) return [];
    final sampled = _downsample(routePoints, _maxRouteSamplePoints);
    final raw = await _searchRaw(
      centers: sampled,
      radiusMeters: corridorRadiusMeters,
      categories: categories,
    );
    final withDistance = raw
        .map((p) => p.withDistance(
              NavigationGeometry.distanceToRoute(LatLng(p.lat, p.lon), routePoints),
            ))
        .toList()
      ..sort((a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0));
    return withDistance.take(_maxResults).toList();
  }

  /// Splits the requested categories between Geoapify (fast, reliable,
  /// needs a key) and Overpass (restrooms only), runs both providers in
  /// parallel, and returns the combined, undeduplicated, un-distanced
  /// results - both `searchNear` and `searchAlongRoute` sort/trim after
  /// this.
  Future<List<Poi>> _searchRaw({
    required List<LatLng> centers,
    required double radiusMeters,
    required Set<String> categories,
  }) async {
    final useGeoapify = geoapifyApiKey.isNotEmpty;
    final geoCategories = useGeoapify
        ? categories.where(_geoapifyCategoryTags.containsKey).toSet()
        : <String>{};
    final overpassCategories = categories.difference(geoCategories);

    final futures = <Future<List<Poi>>>[];
    if (geoCategories.isNotEmpty) {
      futures.add(_searchGeoapify(centers: centers, radiusMeters: radiusMeters, categories: geoCategories));
    }
    if (overpassCategories.isNotEmpty) {
      futures.add(_searchOverpass(centers: centers, radiusMeters: radiusMeters, categories: overpassCategories));
    }
    if (futures.isEmpty) return [];
    if (futures.length == 1) return futures.single;

    // Both providers run concurrently; if one throws, still return
    // whatever the other found rather than failing the whole search.
    final settled = await Future.wait(futures.map((f) => f.then<Object>((v) => v).catchError((Object e) => e)));
    final results = <Poi>[];
    Object? error;
    for (final outcome in settled) {
      if (outcome is List<Poi>) {
        results.addAll(outcome);
      } else {
        error = outcome;
      }
    }
    if (results.isEmpty && error != null) throw error;
    return results;
  }

  // ---------------------------------------------------------------------
  // Geoapify
  // ---------------------------------------------------------------------

  Future<List<Poi>> _searchGeoapify({
    required List<LatLng> centers,
    required double radiusMeters,
    required Set<String> categories,
  }) async {
    final tags = categories.expand((c) => _geoapifyCategoryTags[c] ?? const <String>[]).toSet();
    if (tags.isEmpty || centers.isEmpty) return [];

    if (centers.length == 1) {
      return _geoapifyCircle(center: centers.single, radiusMeters: radiusMeters, tags: tags, requestedCategories: categories);
    }

    // No single-call "corridor" filter in the Places API, so one small
    // circle request per sampled route point, run in parallel and
    // deduplicated - still far fewer round-trips than points, and each
    // one is cheap and fast against Geoapify's own infrastructure.
    final byKey = <String, Poi>{};
    Object? lastError;
    var successes = 0;
    await Future.wait(centers.map((center) async {
      try {
        final pois = await _geoapifyCircle(
          center: center,
          radiusMeters: radiusMeters,
          tags: tags,
          requestedCategories: categories,
        );
        successes++;
        for (final poi in pois) {
          byKey['${poi.lat.toStringAsFixed(5)},${poi.lon.toStringAsFixed(5)},${poi.name}'] = poi;
        }
      } catch (e) {
        lastError = e;
      }
    }));
    if (successes == 0 && lastError != null) throw lastError!;
    return byKey.values.toList();
  }

  Future<List<Poi>> _geoapifyCircle({
    required LatLng center,
    required double radiusMeters,
    required Set<String> tags,
    required Set<String> requestedCategories,
  }) async {
    final uri = Uri.https('api.geoapify.com', '/v2/places', {
      'categories': tags.join(','),
      'filter': 'circle:${center.longitude},${center.latitude},${radiusMeters.round()}',
      'limit': '$_maxResults',
      'apiKey': geoapifyApiKey,
    });
    http.Response response;
    try {
      response = await http.get(uri).timeout(_geoapifyTimeout);
    } on SocketException {
      throw Exception('No internet connection. Check your network and try again.');
    } on TimeoutException {
      throw Exception('That server took too long to respond.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Geoapify rejected the API key - check geoapifyApiKey in poi_service.dart.');
    }
    if (response.statusCode != 200) {
      debugPrint('Geoapify: HTTP ${response.statusCode} - ${response.body}');
      throw Exception('Nearby-places lookup failed (HTTP ${response.statusCode}).');
    }
    return _parseGeoapify(response.body, requestedCategories);
  }

  List<Poi> _parseGeoapify(String body, Set<String> requestedCategories) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? [];
    final results = <Poi>[];
    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      double? lon = (coords != null && coords.isNotEmpty) ? (coords[0] as num?)?.toDouble() : null;
      double? lat = (coords != null && coords.length > 1) ? (coords[1] as num?)?.toDouble() : null;
      lat ??= (props['lat'] as num?)?.toDouble();
      lon ??= (props['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final tags = (props['categories'] as List<dynamic>?)?.cast<String>() ?? const <String>[];
      final category = _appCategoryForGeoapifyTags(tags, requestedCategories);
      if (category == null) continue;

      final name = (props['name'] as String?)?.trim();
      results.add(Poi(
        name: (name != null && name.isNotEmpty) ? name : _fallbackNameForCategory(category),
        category: category,
        lat: lat,
        lon: lon,
      ));
    }
    return results;
  }

  String? _appCategoryForGeoapifyTags(List<String> tags, Set<String> requestedCategories) {
    for (final appCategory in requestedCategories) {
      final geoTags = _geoapifyCategoryTags[appCategory];
      if (geoTags == null) continue;
      if (tags.any((t) => geoTags.any((g) => t == g || t.startsWith('$g.')))) {
        return appCategory;
      }
    }
    return null;
  }

  String _fallbackNameForCategory(String category) {
    switch (category) {
      case 'food':
        return 'Food';
      case 'fuel':
        return 'Fuel station';
      case 'atm_bank':
        return 'ATM / Bank';
      case 'pharmacy':
        return 'Pharmacy';
      default:
        return 'Place';
    }
  }

  // ---------------------------------------------------------------------
  // Overpass (OpenStreetMap) - restrooms only.
  // ---------------------------------------------------------------------

  /// Evenly picks at most [maxPoints] points from [points] (always
  /// keeping the last one) so a full route polyline with hundreds of
  /// points doesn't turn into an unreasonably large request.
  List<LatLng> _downsample(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final step = points.length / maxPoints;
    final sampled = <LatLng>[];
    for (var i = 0; i < maxPoints; i++) {
      sampled.add(points[(i * step).floor()]);
    }
    if (sampled.last != points.last) sampled.add(points.last);
    return sampled;
  }

  Future<List<Poi>> _searchOverpass({
    required List<LatLng> centers,
    required double radiusMeters,
    required Set<String> categories,
  }) async {
    final tags = categories.expand((c) => _categoryAmenityTags[c] ?? const <String>[]).toSet();
    if (tags.isEmpty || centers.isEmpty) return [];
    final tagRegex = tags.join('|');
    final coords = centers.map((p) => '${p.latitude},${p.longitude}').join(',');
    final aroundFilter = 'around:${radiusMeters.round()},$coords';

    // Nodes only, not ways: matching a way and computing its center is
    // meaningfully more expensive for the server than a plain point
    // lookup, and restrooms are overwhelmingly mapped as single points
    // on OSM - this trades a small amount of recall for real speed.
    final query = '[out:json][timeout:$_overpassQueryTimeoutSeconds];'
        'node["amenity"~"^($tagRegex)\$"]($aroundFilter);'
        'out center $_maxResults;';

    final completer = Completer<List<Poi>>();
    var pending = _overpassHosts.length;
    var sawRateLimit = false;
    Object? lastError;

    void fail(Object error, {bool rateLimited = false}) {
      pending--;
      if (rateLimited) sawRateLimit = true;
      lastError = error;
      if (pending == 0 && !completer.isCompleted) {
        if (sawRateLimit) {
          completer.completeError(Exception(
            "OpenStreetMap's nearby-places service is busy right now. Wait a minute and try again.",
          ));
        } else {
          completer.completeError(
            lastError ?? Exception('Nearby-places lookup failed.'),
          );
        }
      }
    }

    for (final host in _overpassHosts) {
      // POST, not GET: overpass-api.de's front end has returned HTTP 406
      // for some GET requests carrying a full query in the URL - POSTing
      // the query as form data is Overpass's own documented, more
      // robust way to run anything beyond a trivial query.
      final uri = Uri.https(host.hostname, host.path);
      http
          .post(
            uri,
            body: {'data': query},
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'travel_planner (Flutter OSM travel planner app)',
            },
          )
          .timeout(_perAttemptTimeout)
          .then((response) {
        if (completer.isCompleted) return;
        if (response.statusCode == 200) {
          completer.complete(_parseOverpassElements(response.body));
          return;
        }
        if (response.statusCode == 429) {
          debugPrint('Overpass ${host.hostname}: rate limited (429)');
          fail(Exception('Rate limited'), rateLimited: true);
          return;
        }
        debugPrint('Overpass ${host.hostname}: HTTP ${response.statusCode}');
        fail(Exception('Nearby-places lookup failed (HTTP ${response.statusCode}).'));
      }).catchError((Object e) {
        if (completer.isCompleted) return;
        debugPrint('Overpass ${host.hostname}: $e');
        if (e is SocketException) {
          fail(Exception('No internet connection. Check your network and try again.'));
        } else if (e is TimeoutException) {
          fail(Exception('That server took too long to respond.'));
        } else {
          fail(e);
        }
      });
    }

    return completer.future;
  }

  List<Poi> _parseOverpassElements(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];
    final results = <Poi>[];
    for (final e in elements) {
      final el = e as Map<String, dynamic>;
      final tagsMap = el['tags'] as Map<String, dynamic>? ?? {};
      final amenity = tagsMap['amenity'] as String?;
      final category = _categoryForAmenity(amenity);
      if (category == null) continue;

      var lat = (el['lat'] as num?)?.toDouble();
      var lon = (el['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        final center = el['center'] as Map<String, dynamic>?;
        lat = (center?['lat'] as num?)?.toDouble();
        lon = (center?['lon'] as num?)?.toDouble();
      }
      if (lat == null || lon == null) continue;

      final name = (tagsMap['name'] as String?)?.trim();
      results.add(Poi(
        name: (name != null && name.isNotEmpty) ? name : _fallbackName(amenity),
        category: category,
        lat: lat,
        lon: lon,
      ));
    }
    return results;
  }

  String? _categoryForAmenity(String? amenity) {
    if (amenity == null) return null;
    for (final entry in _categoryAmenityTags.entries) {
      if (entry.value.contains(amenity)) return entry.key;
    }
    return null;
  }

  String _fallbackName(String? amenity) {
    switch (amenity) {
      case 'restaurant':
        return 'Restaurant';
      case 'cafe':
        return 'Cafe';
      case 'fast_food':
        return 'Fast food';
      case 'toilets':
        return 'Public toilets';
      case 'fuel':
        return 'Fuel station';
      case 'atm':
        return 'ATM';
      case 'bank':
        return 'Bank';
      case 'pharmacy':
        return 'Pharmacy';
      default:
        return 'Place';
    }
  }
}

class _OverpassHost {
  const _OverpassHost(this.hostname, this.path);
  final String hostname;
  final String path;
}
