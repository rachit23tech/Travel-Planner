import 'package:flutter/material.dart';

import '../models/place.dart';

/// The full search history, in its own sheet instead of crowded into
/// the shortcuts row: every past search, newest first, swipe to remove
/// one, or clear the whole list.
class HistorySheet extends StatelessWidget {
  final List<Place> places;
  final ValueChanged<Place> onSelect;
  final ValueChanged<Place> onRemove;
  final VoidCallback onClearAll;

  const HistorySheet({
    super.key,
    required this.places,
    required this.onSelect,
    required this.onRemove,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('History', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (places.isNotEmpty)
                    TextButton(
                      onPressed: onClearAll,
                      child: const Text('Clear all'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: places.isEmpty
                  ? const Center(child: Text('Places you search for will show up here.'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: places.length,
                      itemBuilder: (context, index) {
                        final place = places[index];
                        return Dismissible(
                          key: ValueKey('${place.displayName}-${place.lat}-${place.lon}'),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => onRemove(place),
                          background: Container(
                            color: Theme.of(context).colorScheme.errorContainer,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.onErrorContainer,
                            ),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(place.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => onSelect(place),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
