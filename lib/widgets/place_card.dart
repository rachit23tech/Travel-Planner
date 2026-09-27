import 'package:flutter/material.dart';

import '../models/place.dart';

/// The compact "you picked a place" card shown above the map after a
/// browse-mode search, mirroring Google Maps' result card: a name plus a
/// single obvious way to get directions to it.
class PlaceCard extends StatelessWidget {
  final Place place;
  final VoidCallback onDirections;
  final VoidCallback onClose;

  const PlaceCard({
    super.key,
    required this.place,
    required this.onDirections,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                place.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onDirections,
              icon: const Icon(Icons.directions),
              label: const Text('Directions'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClose,
              tooltip: 'Clear',
            ),
          ],
        ),
      ),
    );
  }
}
