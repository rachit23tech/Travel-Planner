import 'package:flutter/material.dart';

import '../models/route_result.dart';

/// Maps an OSRM maneuver (type + modifier) to a representative turn
/// arrow icon. Shared by the turn-by-turn step list and the live
/// navigation HUD so both read the same way.
IconData iconForManeuver(RouteStep step) {
  final modifier = step.maneuverModifier ?? '';
  switch (step.maneuverType) {
    case 'depart':
      return Icons.trip_origin;
    case 'arrive':
      return Icons.flag;
    case 'roundabout':
    case 'rotary':
      return Icons.roundabout_left;
    case 'merge':
      return Icons.merge;
    case 'fork':
      return Icons.call_split;
    case 'turn':
    case 'end of road':
      if (modifier == 'uturn') return Icons.u_turn_left;
      if (modifier.contains('sharp left')) return Icons.turn_sharp_left;
      if (modifier.contains('sharp right')) return Icons.turn_sharp_right;
      if (modifier.contains('slight left')) return Icons.turn_slight_left;
      if (modifier.contains('slight right')) return Icons.turn_slight_right;
      if (modifier.contains('left')) return Icons.turn_left;
      if (modifier.contains('right')) return Icons.turn_right;
      return Icons.straight;
    default:
      return Icons.straight;
  }
}
