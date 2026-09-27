import 'package:flutter/material.dart';

import '../models/route_result.dart';
import '../utils/maneuver_icons.dart';

/// Bottom sheet showing the route's distance/duration, any alternative
/// routes OSRM offered for the current mode, and a scrollable turn-by-turn
/// step list.
class RouteInfoPanel extends StatelessWidget {
  final RouteResult route;
  final List<RouteResult> alternatives;
  final int selectedIndex;
  final ValueChanged<int> onSelectAlternative;
  final VoidCallback onClose;
  final VoidCallback onStartNavigation;
  final VoidCallback? onDownloadOffline;
  final bool downloadingOffline;

  const RouteInfoPanel({
    super.key,
    required this.route,
    required this.onClose,
    required this.onSelectAlternative,
    required this.onStartNavigation,
    this.alternatives = const [],
    this.selectedIndex = 0,
    this.onDownloadOffline,
    this.downloadingOffline = false,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.34,
      minChildSize: 0.12,
      maxChildSize: 0.8,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (alternatives.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: alternatives.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final alt = alternatives[index];
                        return ChoiceChip(
                          label: Text('Route ${index + 1} · ${alt.durationLabel}'),
                          selected: index == selectedIndex,
                          onSelected: (_) => onSelectAlternative(index),
                        );
                      },
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.route),
                      const SizedBox(width: 8),
                      Text(
                        '${route.distanceLabel}  ·  ${route.durationLabel}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onStartNavigation,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Start Navigation'),
                    ),
                  ),
                  if (onDownloadOffline != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: downloadingOffline ? null : onDownloadOffline,
                      icon: downloadingOffline
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_for_offline),
                      label: const Text('Offline'),
                    ),
                  ],
                ],
              ),
              const Divider(),
              if (route.steps.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No turn-by-turn steps were returned for this route.'),
                ),
              ...route.steps.map((step) {
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Icon(iconForManeuver(step), size: 16),
                  ),
                  title: Text(step.instruction),
                  trailing: step.distanceMeters > 0
                      ? Text('${step.distanceMeters.round()} m')
                      : null,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
