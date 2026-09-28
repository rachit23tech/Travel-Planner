import 'package:latlong2/latlong.dart';

import '../models/combo_stop.dart';
import '../models/poi.dart';
import '../models/route_result.dart';
import '../utils/navigation_geometry.dart';
import 'poi_service.dart';

/// Proactively plans rest stops for a long drive, instead of waiting
/// for the driver to think to search: for a trip over [_minTripDuration],
/// it samples the route roughly every [_interval] of driving time and
/// finds what's clustered around each sample point - fuel, food, a
/// restroom, all close together - the same way you'd actually plan a
/// road trip's stops in advance, which no turn-by-turn app surfaces
/// automatically.
class TripBreakPlanner {
  final PoiService _poiService;

  const TripBreakPlanner(this._poiService);

  static const _interval = Duration(hours: 2);
  static const _minTripDuration = Duration(minutes: 90);
  static const _maxStops = 4;
  static const _searchRadiusMeters = 3000.0;
  static const _categories = {'food', 'fuel', 'atm_bank', 'pharmacy', 'restroom'};

  Future<List<ComboStop>> planBreaks(RouteResult route) async {
    final totalSeconds = route.durationSeconds;
    if (totalSeconds < _minTripDuration.inSeconds || route.points.length < 2) {
      return [];
    }

    final intervalSeconds = _interval.inSeconds;
    final stopCount = (totalSeconds / intervalSeconds).floor().clamp(0, _maxStops);
    if (stopCount < 1) return [];

    final cumulative = _cumulativeDistances(route.points);
    final totalDistance = cumulative.last;
    if (totalDistance <= 0) return [];

    // One sample point per planned stop, at an even fraction of the
    // route's total distance - searched concurrently since each is an
    // independent lookup, and one interval's failure shouldn't hold up
    // the others.
    final samplePoints = <LatLng>[];
    final timesIntoTrip = <Duration>[];
    for (var k = 1; k <= stopCount; k++) {
      final fraction = (k * intervalSeconds) / totalSeconds;
      if (fraction >= 1) break;
      samplePoints.add(_pointAtDistance(route.points, cumulative, fraction * totalDistance));
      timesIntoTrip.add(Duration(seconds: k * intervalSeconds));
    }

    final searches = samplePoints.map((point) {
      return _poiService
          .searchNear(center: point, radiusMeters: _searchRadiusMeters, categories: _categories)
          .then<List<Poi>?>((pois) => pois)
          .catchError((_) => null);
    }).toList();
    final resultsByPoint = await Future.wait(searches);

    final stops = <ComboStop>[];
    for (var i = 0; i < resultsByPoint.length; i++) {
      final pois = resultsByPoint[i];
      if (pois == null || pois.isEmpty) continue;
      final byCategory = <String, Poi>{};
      for (final poi in pois) {
        byCategory.putIfAbsent(poi.category, () => poi);
      }
      stops.add(ComboStop(
        location: LatLng(pois.first.lat, pois.first.lon),
        timeIntoTrip: timesIntoTrip[i],
        anchor: pois.first,
        nearbyByCategory: byCategory.values.toList(),
      ));
    }
    return stops;
  }

  List<double> _cumulativeDistances(List<LatLng> points) {
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + NavigationGeometry.distanceMeters(points[i - 1], points[i]));
    }
    return cumulative;
  }

  LatLng _pointAtDistance(List<LatLng> points, List<double> cumulative, double targetDistance) {
    for (var i = 0; i < cumulative.length; i++) {
      if (cumulative[i] >= targetDistance) return points[i];
    }
    return points.last;
  }
}
