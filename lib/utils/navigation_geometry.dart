import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Off-route detection and maneuver-proximity math for live navigation.
///
/// Distances to a single point use real Haversine distance (via
/// [Distance]). Distance to the route polyline projects onto each
/// segment using a flat equirectangular approximation local to that
/// segment - accurate to well under a meter over the short (tens of
/// meters) segment lengths OSRM's geometry is made of, and much cheaper
/// than true great-circle segment projection. More than good enough for
/// an off-route threshold measured in tens of meters.
class NavigationGeometry {
  static const _metersPerDegreeLat = 111320.0;
  static const _distance = Distance();

  /// Straight-line distance in meters between two points.
  static double distanceMeters(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);

  /// The shortest distance in meters from [point] to the polyline
  /// [route], checking every segment. Returns [double.infinity] for an
  /// empty route.
  static double distanceToRoute(LatLng point, List<LatLng> route) {
    if (route.isEmpty) return double.infinity;
    if (route.length == 1) return distanceMeters(point, route.first);
    var best = double.infinity;
    for (var i = 0; i < route.length - 1; i++) {
      final d = _distanceToSegment(point, route[i], route[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    final mPerDegLon = _metersPerDegreeLat * cos(a.latitude * pi / 180);

    final bx = (b.longitude - a.longitude) * mPerDegLon;
    final by = (b.latitude - a.latitude) * _metersPerDegreeLat;
    final px = (p.longitude - a.longitude) * mPerDegLon;
    final py = (p.latitude - a.latitude) * _metersPerDegreeLat;

    final abLenSq = bx * bx + by * by;
    final t = abLenSq == 0
        ? 0.0
        : ((px * bx + py * by) / abLenSq).clamp(0.0, 1.0);
    final projX = t * bx;
    final projY = t * by;
    final dx = px - projX;
    final dy = py - projY;
    return sqrt(dx * dx + dy * dy);
  }
}
