import 'package:flutter/material.dart';

import '../models/poi.dart';
import '../utils/poi_style.dart';

/// A bottom sheet for finding food stops, restrooms, fuel, ATMs/banks,
/// or pharmacies: pick a category, see the results (nearest first),
/// tap one. What "nearby" means is entirely up to [onSearch] - the
/// caller decides whether that's near the device's current location or
/// along a route's corridor.
class NearbySheet extends StatefulWidget {
  final String title;
  final Future<List<Poi>> Function(Set<String> categories) onSearch;
  final ValueChanged<Poi> onSelect;

  const NearbySheet({
    super.key,
    required this.onSearch,
    required this.onSelect,
    this.title = 'Nearby',
  });

  @override
  State<NearbySheet> createState() => _NearbySheetState();
}

class _NearbySheetState extends State<NearbySheet> {
  String? _selectedCategory;
  bool _loading = false;
  String? _error;
  List<Poi> _results = [];

  Future<void> _selectCategory(String category) async {
    setState(() {
      _selectedCategory = category;
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await widget.onSearch({category});
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _distanceLabel(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: poiCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = poiCategories[index];
                    return ChoiceChip(
                      avatar: Icon(iconForPoiCategory(category), size: 18),
                      label: Text(labelForPoiCategory(category)),
                      selected: _selectedCategory == category,
                      onSelected: (_) => _selectCategory(category),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_selectedCategory == null) {
      return const Center(child: Text("Pick a category to see what's nearby."));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('Nothing found nearby for this category.'));
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final poi = _results[index];
        return ListTile(
          leading: CircleAvatar(child: Icon(iconForPoiCategory(poi.category), size: 20)),
          title: Text(poi.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: poi.distanceMeters != null
              ? Text(_distanceLabel(poi.distanceMeters!))
              : null,
          onTap: () => widget.onSelect(poi),
        );
      },
    );
  }
}
