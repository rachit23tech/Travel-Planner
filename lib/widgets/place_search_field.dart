import 'dart:async';

import 'package:flutter/material.dart';

import '../models/place.dart';
import '../services/geocoding_service.dart';

/// A text field that searches Nominatim as the user types (debounced) and
/// shows a tappable list of matching places underneath.
class PlaceSearchField extends StatefulWidget {
  final String label;
  final IconData icon;
  final Place? selectedPlace;
  final ValueChanged<Place> onPlaceSelected;
  final VoidCallback? onUseCurrentLocation;

  const PlaceSearchField({
    super.key,
    required this.label,
    required this.icon,
    required this.onPlaceSelected,
    this.selectedPlace,
    this.onUseCurrentLocation,
  });

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  final _controller = TextEditingController();
  final _geocodingService = GeocodingService();
  Timer? _debounce;
  List<Place> _results = [];
  bool _loading = false;
  String? _lastErrorShown;

  @override
  void initState() {
    super.initState();
    if (widget.selectedPlace != null) {
      _controller.text = widget.selectedPlace!.displayName;
    }
  }

  @override
  void didUpdateWidget(covariant PlaceSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selectedPlace;
    if (selected != null && selected.displayName != _controller.text) {
      _controller.text = selected.displayName;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Fires only once typing pauses, so continuous typing doesn't spam
    // Nominatim's ~1 req/sec usage-policy limit - it just feels live
    // because the pause is short.
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (value.trim().length < 2) {
        if (mounted) setState(() => _results = []);
        return;
      }
      if (mounted) setState(() => _loading = true);
      try {
        final results = await _geocodingService.search(value);
        if (!mounted) return;
        setState(() {
          _results = results;
          _loading = false;
          _lastErrorShown = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _results = [];
          _loading = false;
        });
        // Surface the real reason (e.g. Nominatim returning HTTP 403)
        // instead of silently showing nothing - but only once per
        // distinct error, so it doesn't spam a SnackBar on every
        // keystroke while the server keeps failing.
        final message = e.toString();
        if (message != _lastErrorShown) {
          _lastErrorShown = message;
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
          }
        }
      }
    });
  }

  void _select(Place place) {
    setState(() {
      _controller.text = place.displayName;
      _results = [];
    });
    FocusScope.of(context).unfocus();
    widget.onPlaceSelected(place);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            prefixIcon: Icon(widget.icon),
            labelText: widget.label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: widget.onUseCurrentLocation != null
                ? IconButton(
                    icon: const Icon(Icons.my_location),
                    tooltip: 'Use current location',
                    onPressed: widget.onUseCurrentLocation,
                  )
                : (_loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null),
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final place = _results[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    place.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _select(place),
                );
              },
            ),
          ),
      ],
    );
  }
}
