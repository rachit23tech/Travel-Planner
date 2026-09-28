import 'package:flutter/material.dart';

import '../models/route_result.dart';
import '../utils/maneuver_icons.dart';

/// The live-navigation instruction banner: the upcoming turn, distance to
/// it, and rerouting/arrival status - styled after Google Maps' compact
/// turn-by-turn card (big arrow chip + big distance, not a full screen
/// takeover). Shown in place of the itinerary bar while navigating.
class NavigationHud extends StatelessWidget {
  final RouteStep? upcomingStep;
  final double? distanceToManeuverMeters;
  final bool rerouting;
  final bool arrived;
  final VoidCallback onStop;
  final bool voiceEnabled;
  final VoidCallback? onToggleVoice;
  final VoidCallback? onShare;
  final bool sharingActive;

  const NavigationHud({
    super.key,
    required this.upcomingStep,
    required this.distanceToManeuverMeters,
    required this.onStop,
    this.rerouting = false,
    this.arrived = false,
    this.voiceEnabled = true,
    this.onToggleVoice,
    this.onShare,
    this.sharingActive = false,
  });

  String _distanceLabel(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final distance = distanceToManeuverMeters;
    final onPrimary = Theme.of(context).colorScheme.onPrimaryContainer;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The turn-arrow "chip" - Maps' signature big rounded icon.
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: onPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                arrived
                    ? Icons.flag
                    : (upcomingStep != null
                        ? iconForManeuver(upcomingStep!)
                        : Icons.straight),
                size: 30,
                color: onPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rerouting
                    ? [
                        Text(
                          'Rerouting…',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ]
                    : [
                        Text(
                          arrived
                              ? 'Arriving'
                              : (distance != null
                                  ? _distanceLabel(distance)
                                  : '—'),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          arrived
                              ? 'You have reached your destination'
                              : (upcomingStep?.instruction ?? 'Follow the route'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: onPrimary),
                        ),
                      ],
              ),
            ),
            if (onShare != null)
              IconButton(
                icon: Icon(
                  sharingActive ? Icons.groups : Icons.share_location,
                  color: onPrimary,
                ),
                tooltip: sharingActive ? 'Sharing this trip' : 'Share this trip',
                onPressed: onShare,
              ),
            if (onToggleVoice != null)
              IconButton(
                icon: Icon(
                  voiceEnabled ? Icons.volume_up : Icons.volume_off,
                  color: onPrimary,
                ),
                tooltip: voiceEnabled ? 'Mute voice guidance' : 'Unmute voice guidance',
                onPressed: onToggleVoice,
              ),
            IconButton(
              icon: Icon(Icons.close, color: onPrimary),
              tooltip: 'Stop navigation',
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}
