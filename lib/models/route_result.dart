import 'package:latlong2/latlong.dart';

/// One turn-by-turn instruction within a route.
class RouteStep {
  final String instruction;
  final double distanceMeters;
  final String maneuverType;
  final String? maneuverModifier;

  /// Where this maneuver happens, from OSRM's `maneuver.location`. Used
  /// by live navigation to know how far the device is from the next
  /// turn, and to detect when a step has been completed.
  final LatLng? location;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.maneuverType,
    this.maneuverModifier,
    this.location,
  });
}

/// The result of an OSRM routing request: the line to draw on the map,
/// the trip totals, and the turn-by-turn steps.
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });

  String get distanceLabel {
    final km = distanceMeters / 1000;
    return '${km.toStringAsFixed(1)} km';
  }

  String get durationLabel {
    final totalMinutes = (durationSeconds / 60).round();
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}min';
  }
}
