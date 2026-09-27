import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../models/route_result.dart';
import 'network_client.dart';

enum TravelMode { driving, walking, cycling }

extension _TravelModeUrl on TravelMode {
  /// Public, best-effort OSRM demo servers - fine for trying this app out,
  /// but rate-limited and not meant for production use. Self-host OSRM
  /// (https://project-osrm.org/) for anything real.
  String get baseUrl {
    switch (this) {
      case TravelMode.driving:
        return 'https://router.project-osrm.org/route/v1/driving';
      case TravelMode.walking:
        return 'https://routing.openstreetmap.de/routed-foot/route/v1/foot';
      case TravelMode.cycling:
        return 'https://routing.openstreetmap.de/routed-bike/route/v1/bike';
    }
  }
}

/// Talks to an OSRM `/route/v1` endpoint to get route(s) through an
/// ordered list of [Place] waypoints (start, any via stops, then the
/// final destination - at least 2 required).
class RoutingService {
  /// The full route for [mode], plus any alternatives OSRM offers for it
  /// (there's often only one - multi-waypoint trips in particular rarely
  /// get alternatives from the public demo server). The first entry is
  /// OSRM's own recommended route.
  Future<List<RouteResult>> getRouteAlternatives({
    required List<Place> waypoints,
    required TravelMode mode,
  }) {
    return _request(
      waypoints: waypoints,
      mode: mode,
      full: true,
      alternatives: true,
    );
  }

  /// The single recommended route for [mode], with full geometry and
  /// turn-by-turn steps.
  Future<RouteResult> getRoute({
    required List<Place> waypoints,
    required TravelMode mode,
  }) async {
    final routes = await _request(
      waypoints: waypoints,
      mode: mode,
      full: true,
      alternatives: false,
    );
    return routes.first;
  }

  /// A lightweight distance/duration-only request (no geometry or steps)
  /// for [mode] - used to show an ETA preview under a mode button before
  /// the user has actually picked that mode.
  Future<RouteResult> getRoutePreview({
    required List<Place> waypoints,
    required TravelMode mode,
  }) async {
    final routes = await _request(
      waypoints: waypoints,
      mode: mode,
      full: false,
      alternatives: false,
    );
    return routes.first;
  }

  Future<List<RouteResult>> _request({
    required List<Place> waypoints,
    required TravelMode mode,
    required bool full,
    required bool alternatives,
  }) async {
    if (waypoints.length < 2) {
      throw ArgumentError('At least a start and an end point are required.');
    }

    final coords = waypoints.map((p) => '${p.lon},${p.lat}').join(';');
    final uri = Uri.parse('${mode.baseUrl}/$coords').replace(
      queryParameters: {
        'overview': full ? 'full' : 'false',
        'geometries': 'geojson',
        'steps': full ? 'true' : 'false',
        if (alternatives) 'alternatives': 'true',
      },
    );

    final response = await getWithRetry(uri);

    if (response.statusCode != 200) {
      throw Exception('Routing request failed (HTTP ${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (data['code'] != 'Ok') {
      throw Exception('No route could be calculated (${data['code']}).');
    }

    final routesJson = data['routes'] as List<dynamic>? ?? [];
    if (routesJson.isEmpty) {
      throw Exception('No route found through these stops.');
    }

    return routesJson
        .map((r) => _parseRoute(r as Map<String, dynamic>))
        .toList();
  }

  RouteResult _parseRoute(Map<String, dynamic> route) {
    // geometry/steps are omitted by OSRM entirely for a preview request
    // (overview=false, steps=false), so both are parsed defensively.
    final geometryJson = route['geometry'] as Map<String, dynamic>?;
    var points = <LatLng>[];
    if (geometryJson != null) {
      final coordinates = geometryJson['coordinates'] as List<dynamic>;
      points = coordinates.map((c) {
        final pair = c as List<dynamic>;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
    }

    final steps = <RouteStep>[];
    final legs = route['legs'] as List<dynamic>? ?? [];
    for (final leg in legs) {
      final legSteps = (leg as Map<String, dynamic>)['steps'] as List<dynamic>?;
      if (legSteps == null) continue;
      for (final step in legSteps) {
        final s = step as Map<String, dynamic>;
        final maneuver = s['maneuver'] as Map<String, dynamic>? ?? {};
        final type = maneuver['type'] as String? ?? 'continue';
        final modifier = maneuver['modifier'] as String?;
        final roadName = (s['name'] as String?)?.trim() ?? '';
        final locationJson = maneuver['location'] as List<dynamic>?;
        final location = locationJson != null
            ? LatLng(
                (locationJson[1] as num).toDouble(),
                (locationJson[0] as num).toDouble(),
              )
            : null;
        steps.add(RouteStep(
          instruction: _describeStep(type, modifier, roadName),
          distanceMeters: (s['distance'] as num?)?.toDouble() ?? 0,
          maneuverType: type,
          maneuverModifier: modifier,
          location: location,
        ));
      }
    }

    return RouteResult(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      steps: steps,
    );
  }

  String _describeStep(String type, String? modifier, String roadName) {
    final onRoad = roadName.isNotEmpty ? ' onto $roadName' : '';
    switch (type) {
      case 'depart':
        return roadName.isNotEmpty ? 'Start on $roadName' : 'Start your trip';
      case 'arrive':
        return 'Arrive at your destination';
      case 'turn':
        return ('Turn ${modifier ?? ''}$onRoad').trim();
      case 'roundabout':
      case 'rotary':
        return 'Enter the roundabout$onRoad';
      case 'merge':
        return (modifier != null ? 'Merge $modifier$onRoad' : 'Merge$onRoad').trim();
      case 'fork':
        return 'Keep ${modifier ?? 'straight'}$onRoad';
      case 'end of road':
        return ('At the end of the road, turn ${modifier ?? ''}$onRoad').trim();
      case 'continue':
        return 'Continue$onRoad'.trim();
      default:
        final label = type.isNotEmpty
            ? '${type[0].toUpperCase()}${type.substring(1)}'
            : 'Continue';
        return '$label$onRoad'.trim();
    }
  }
}
