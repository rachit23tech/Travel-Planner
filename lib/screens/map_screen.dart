import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/combo_stop.dart';
import '../models/place.dart';
import '../models/poi.dart';
import '../models/route_result.dart';
import '../models/trip_share.dart';
import '../services/geocoding_service.dart';
import '../services/auth_service.dart';
import '../services/poi_service.dart';
import '../services/routing_service.dart';
import '../services/saved_places_service.dart';
import '../services/trip_break_planner.dart';
import '../services/trip_share_service.dart';
import '../services/voice_guidance_service.dart';
import '../services/offline_maps_service.dart';
import '../utils/navigation_geometry.dart';
import '../widgets/history_sheet.dart';
import '../widgets/nearby_sheet.dart';
import '../widgets/navigation_hud.dart';
import '../widgets/place_card.dart';
import '../widgets/place_search_field.dart';
import '../widgets/route_info_panel.dart';
import '../widgets/trip_share_sheet.dart';

/// Mirrors Google Maps' own flow, not its visuals: browse/search first,
/// then step into "directions" only once the user asks for a route.
enum _ScreenMode { browse, directions }

/// One slot in the itinerary. [id] is stable across reordering/insertion
/// so PlaceSearchField's widget identity (and internal text controller)
/// never gets attached to the wrong logical stop.
class _StopEntry {
  final int id;
  Place? place;
  _StopEntry(this.id, [this.place]);
}

class MapScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback? onRequestSignIn;

  const MapScreen({
    super.key,
    required this.authService,
    this.onRequestSignIn,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final GeocodingService _geocodingService = GeocodingService();
  final RoutingService _routingService = RoutingService();
  final SavedPlacesService _savedPlacesService = SavedPlacesService();
  final PoiService _poiService = PoiService();
  final TripBreakPlanner _breakPlanner = TripBreakPlanner(PoiService());
  final TripShareService _tripShareService = TripShareService();
  final VoiceGuidanceService _voiceService = VoiceGuidanceService();

  static const LatLng _fallbackCenter = LatLng(20.5937, 78.9629); // India
  static const double _fallbackZoom = 4.5;

  _ScreenMode _screenMode = _ScreenMode.browse;

  Place? _searchedPlace; // browse mode: a picked search result
  Place? _home;
  Place? _work;
  List<Place> _recents = [];

  int _nextStopId = 0;
  List<_StopEntry> _stops = []; // directions mode: [start, ...vias, end]

  RouteResult? _route;
  List<RouteResult> _alternatives = [];
  int _selectedAlternativeIndex = 0;
  Map<TravelMode, RouteResult> _previewRoutes = {}; // ETA preview per mode
  TravelMode _mode = TravelMode.driving;

  bool _loadingRoute = false;
  bool _loadingLocation = false;

  // --- Live navigation state ---
  bool _navigating = false;
  bool _rerouting = false;
  bool _arrivedAtDestination = false;
  StreamSubscription<Position>? _positionSub;
  LatLng? _liveMyPosition;
  double? _liveHeading;
  double? _liveSpeedKmh;
  int _navStepIndex = 0;
  DateTime? _lastRerouteAt;
  bool _voiceEnabled = true;
  bool _announcedFarForStep = false;
  bool _announcedNearForStep = false;

  // --- Offline map download state ---
  bool _downloadingOffline = false;
  StreamSubscription<double>? _offlineDownloadSub;

  // --- Suggested rest stops for the current route ---
  List<ComboStop> _suggestedStops = [];

  // --- Live location sharing / convoy ---
  TripShare? _activeShare;
  StreamSubscription<TripShare?>? _shareSub;
  Timer? _shareBroadcastTimer;

  @override
  void initState() {
    super.initState();
    // Like Google Maps, open centered on the user - best effort; if
    // location is denied/unavailable we just keep the default world view.
    _recenterOnMyLocation(showErrors: false);
    _loadSavedPlaces();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _offlineDownloadSub?.cancel();
    _shareSub?.cancel();
    _shareBroadcastTimer?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPlaces() async {
    final home = await _savedPlacesService.getHome();
    final work = await _savedPlacesService.getWork();
    final recents = await _savedPlacesService.getRecents();
    if (!mounted) return;
    setState(() {
      _home = home;
      _work = work;
      _recents = recents;
    });
  }

  /// Records a picked place into recent searches - local state updates
  /// immediately, the on-device save happens in the background.
  void _recordRecent(Place place) {
    _savedPlacesService.addRecent(place);
    setState(() {
      _recents = [
        place,
        ..._recents.where((p) =>
            !(p.displayName == place.displayName &&
                p.lat == place.lat &&
                p.lon == place.lon)),
      ].take(30).toList();
    });
  }

  /// The full search history, in its own sheet rather than crammed into
  /// the shortcuts row - tap an entry to reuse it, swipe one away, or
  /// clear everything.
  Future<void> _showHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return HistorySheet(
              places: _recents,
              onSelect: (place) {
                Navigator.of(sheetContext).pop();
                _onSearchResultSelected(place);
              },
              onRemove: (place) {
                setSheetState(() => _recents = _recents.where((p) => p != place).toList());
                _removeRecent(place);
              },
              onClearAll: () {
                Navigator.of(sheetContext).pop();
                _clearRecents();
              },
            );
          },
        );
      },
    );
  }

  void _removeRecent(Place place) {
    _savedPlacesService.removeRecent(place);
    setState(() => _recents = _recents.where((p) => p != place).toList());
  }

  void _clearRecents() {
    _savedPlacesService.clearRecents();
    setState(() => _recents = []);
  }

  Future<void> _promptSetShortcut({required bool isHome}) async {
    Place? picked;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Set ${isHome ? 'Home' : 'Work'}'),
          content: SizedBox(
            width: double.maxFinite,
            child: PlaceSearchField(
              label: 'Search a place',
              icon: Icons.search,
              onPlaceSelected: (place) {
                picked = place;
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (picked == null) return;
    if (isHome) {
      await _savedPlacesService.setHome(picked!);
      if (!mounted) return;
      setState(() => _home = picked);
    } else {
      await _savedPlacesService.setWork(picked!);
      if (!mounted) return;
      setState(() => _work = picked);
    }
  }

  Future<void> _clearShortcut({required bool isHome}) async {
    if (isHome) {
      await _savedPlacesService.clearHome();
      if (!mounted) return;
      setState(() => _home = null);
    } else {
      await _savedPlacesService.clearWork();
      if (!mounted) return;
      setState(() => _work = null);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  _StopEntry _newStop([Place? place]) => _StopEntry(_nextStopId++, place);

  Future<Position> _determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are turned off on this device.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission was denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it from system settings.',
      );
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _recenterOnMyLocation({bool showErrors = true}) async {
    if (showErrors) setState(() => _loadingLocation = true);
    try {
      final position = await _determinePosition();
      if (!mounted) return;
      _mapController.move(LatLng(position.latitude, position.longitude), 15);
      if (showErrors) setState(() => _loadingLocation = false);
    } catch (e) {
      if (!mounted) return;
      if (showErrors) {
        setState(() => _loadingLocation = false);
        _showError(e.toString());
      }
      // Silently ignored on startup (showErrors: false) - default view stays.
    }
  }

  /// Fills a stop slot with the device's current GPS position, reverse
  /// geocoded to a label when possible (falls back to a plain "My
  /// Location" label if that lookup fails - it shouldn't block the flow).
  Future<void> _resolveStopWithMyLocation(int stopId) async {
    setState(() => _loadingLocation = true);
    try {
      final position = await _determinePosition();
      Place place;
      try {
        place = await _geocodingService.reverseGeocode(
          position.latitude,
          position.longitude,
        );
      } catch (_) {
        place = Place(
          displayName: 'My Location',
          lat: position.latitude,
          lon: position.longitude,
        );
      }
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _setStopPlace(stopId, place);
      });
      _maybeFetchRoute();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingLocation = false);
      _showError(e.toString());
    }
  }

  void _setStopPlace(int stopId, Place place) {
    final index = _stops.indexWhere((s) => s.id == stopId);
    if (index == -1) return;
    _stops[index].place = place;
  }

  void _onSearchResultSelected(Place place) {
    setState(() => _searchedPlace = place);
    _mapController.move(LatLng(place.lat, place.lon), 15);
    _recordRecent(place);
  }

  Future<void> _startDirectionsTo(Place destination) async {
    setState(() {
      _screenMode = _ScreenMode.directions;
      _stops = [_newStop(), _newStop(destination)];
      _route = null;
    });
    await _resolveStopWithMyLocation(_stops.first.id);
  }

  void _exitDirections() {
    _positionSub?.cancel();
    _positionSub = null;
    setState(() {
      _navigating = false;
      _rerouting = false;
      _arrivedAtDestination = false;
      _liveMyPosition = null;
      _liveHeading = null;
      _liveSpeedKmh = null;
      _screenMode = _ScreenMode.browse;
      _route = null;
      _alternatives = [];
      _selectedAlternativeIndex = 0;
      _previewRoutes = {};
      _stops = [];
      _suggestedStops = [];
    });
  }

  void _addStop() {
    setState(() {
      // Insert just before the final destination, like Google Maps' own
      // "Add stop" - the last slot always stays the trip's end point.
      _stops.insert(_stops.length - 1, _newStop());
    });
  }

  void _removeStop(int stopId) {
    setState(() => _stops.removeWhere((s) => s.id == stopId));
    _maybeFetchRoute();
  }

  void _maybeFetchRoute() {
    if (_stops.length >= 2 && _stops.every((s) => s.place != null)) {
      _fetchRoute();
    }
  }

  Future<void> _fetchRoute() async {
    final places = _stops.map((s) => s.place).toList();
    if (places.length < 2 || places.any((p) => p == null)) {
      _showError('Fill in every stop before getting a route.');
      return;
    }
    final waypoints = places.cast<Place>();
    setState(() => _loadingRoute = true);

    List<RouteResult> alternatives;
    try {
      alternatives = await _routingService.getRouteAlternatives(
        waypoints: waypoints,
        mode: _mode,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRoute = false);
      _showError(e.toString());
      return;
    }

    // ETA previews for the OTHER two modes, fetched in parallel and each
    // independently tolerant of failure - a mode's preview just stays
    // blank rather than the whole route request failing over it.
    final previews = <TravelMode, RouteResult>{_mode: alternatives.first};
    await Future.wait(TravelMode.values.where((m) => m != _mode).map((m) async {
      try {
        previews[m] = await _routingService.getRoutePreview(
          waypoints: waypoints,
          mode: m,
        );
      } catch (_) {
        // Leave this mode's ETA label blank - it's a nice-to-have.
      }
    }));

    if (!mounted) return;
    setState(() {
      _alternatives = alternatives;
      _selectedAlternativeIndex = 0;
      _route = alternatives.first;
      _previewRoutes = previews;
      _loadingRoute = false;
      _suggestedStops = [];
    });
    _centerOnRoute();
    _updateSuggestedStops();
  }

  void _selectAlternative(int index) {
    if (index < 0 || index >= _alternatives.length) return;
    setState(() {
      _selectedAlternativeIndex = index;
      _route = _alternatives[index];
      _suggestedStops = [];
    });
    _updateSuggestedStops();
  }

  /// Proactively plans rest stops for this route (fuel/food/restroom
  /// clustered together, roughly every 2 hours of driving) - runs in
  /// the background after a route is fetched, so it never blocks the
  /// route preview from showing. Silently does nothing for a short
  /// trip, a slow/failed lookup, or if the route has since changed.
  Future<void> _updateSuggestedStops() async {
    final route = _route;
    if (route == null) return;
    try {
      final stops = await _breakPlanner.planBreaks(route);
      if (!mounted || _route != route) return;
      setState(() => _suggestedStops = stops);
    } catch (_) {
      // Suggested stops are a nice-to-have, not core routing - fail quietly.
    }
  }

  /// Short ETA label for a mode button ("12 min"), blank until a preview
  /// (or the full route, for the selected mode) has been fetched.
  String _previewLabel(TravelMode mode) {
    return _previewRoutes[mode]?.durationLabel ?? '';
  }

  IconData _iconForMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.driving:
        return Icons.directions_car;
      case TravelMode.cycling:
        return Icons.directions_bike;
      case TravelMode.walking:
        return Icons.directions_walk;
    }
  }

  void _centerOnRoute() {
    final places = _stops.map((s) => s.place).whereType<Place>().toList();
    if (places.isEmpty) return;
    final avgLat = places.map((p) => p.lat).reduce((a, b) => a + b) / places.length;
    final avgLon = places.map((p) => p.lon).reduce((a, b) => a + b) / places.length;
    _mapController.move(LatLng(avgLat, avgLon), 12);
  }

  // --- Nearby food/restrooms/fuel/ATM/pharmacy ---

  /// Browse mode: "what's around me right now" - searched from the
  /// device's current GPS position.
  Future<void> _showNearbyFromMyLocation() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return NearbySheet(
          title: 'Nearby',
          onSearch: (categories) async {
            final position = await _determinePosition();
            return _poiService.searchNear(
              center: LatLng(position.latitude, position.longitude),
              radiusMeters: 1500,
              categories: categories,
            );
          },
          onSelect: (poi) {
            Navigator.of(sheetContext).pop();
            _onSearchResultSelected(Place(displayName: poi.name, lat: poi.lat, lon: poi.lon));
          },
        );
      },
    );
  }

  /// Directions mode: "what's along this route" - searched within a
  /// corridor around the currently selected route, picking one adds it
  /// as a via-stop and refetches the route through it.
  Future<void> _showNearbyAlongRoute() async {
    final route = _route;
    if (route == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return NearbySheet(
          title: 'Stops on the way',
          onSearch: (categories) => _poiService.searchAlongRoute(
            routePoints: route.points,
            corridorRadiusMeters: 600,
            categories: categories,
          ),
          onSelect: (poi) {
            Navigator.of(sheetContext).pop();
            _addPoiAsStop(poi);
          },
        );
      },
    );
  }

  void _addPoiAsStop(Poi poi) {
    final place = Place(displayName: poi.name, lat: poi.lat, lon: poi.lon);
    setState(() {
      // Same rule as the manual "Add stop" button - just before the
      // final destination, which always stays the trip's end point.
      _stops.insert(_stops.length - 1, _newStop(place));
    });
    _recordRecent(place);
    _maybeFetchRoute();
  }

  // --- Live navigation ---

  RouteStep? get _upcomingStep {
    final route = _route;
    if (route == null || route.steps.isEmpty) return null;
    final index = _navStepIndex.clamp(0, route.steps.length - 1);
    return route.steps[index];
  }

  double? get _distanceToUpcomingManeuver {
    final route = _route;
    final pos = _liveMyPosition;
    if (route == null || pos == null || route.steps.isEmpty) return null;
    final index = _navStepIndex.clamp(0, route.steps.length - 1);
    final location = route.steps[index].location;
    if (location == null) return null;
    return NavigationGeometry.distanceMeters(pos, location);
  }

  Future<void> _startNavigation() async {
    if (_route == null || _route!.points.isEmpty) return;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are turned off on this device.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showError('Location permission is needed to navigate.');
        return;
      }
    } catch (e) {
      _showError(e.toString());
      return;
    }

    if (!mounted) return;
    setState(() {
      _navigating = true;
      _arrivedAtDestination = false;
      _navStepIndex = (_route!.steps.length > 1) ? 1 : 0;
      _lastRerouteAt = null;
      _announcedFarForStep = false;
      _announcedNearForStep = false;
    });
    _voiceService.setEnabled(_voiceEnabled);
    _voiceService.speak('Starting navigation.');

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(
      _handleNavigationPosition,
      onError: (Object e) => _showError('Lost live location: $e'),
    );
  }

  void _stopNavigation() {
    _positionSub?.cancel();
    _positionSub = null;
    _voiceService.stop();
    if (!mounted) return;
    setState(() {
      _navigating = false;
      _rerouting = false;
      _liveHeading = null;
      _liveSpeedKmh = null;
    });
  }

  /// GPS-derived speed (Doppler, not just position deltas) is noisy at
  /// low speeds, especially with a weak fix - a phone sitting still can
  /// easily report 3-12 km/h of phantom movement. Tiny readings are
  /// floored to zero, and everything else is smoothed against the
  /// previous reading so the displayed number doesn't jump around.
  double _smoothSpeedKmh(double rawSpeedMps) {
    const noiseFloorKmh = 2.0;
    final raw = rawSpeedMps.isFinite ? rawSpeedMps * 3.6 : 0.0;
    final clamped = raw < noiseFloorKmh ? 0.0 : raw;
    final previous = _liveSpeedKmh;
    if (previous == null) return clamped;
    return previous * 0.6 + clamped * 0.4;
  }

  void _handleNavigationPosition(Position position) {
    if (!mounted || !_navigating) return;
    final point = LatLng(position.latitude, position.longitude);
    final smoothedSpeedKmh = _smoothSpeedKmh(position.speed);

    setState(() {
      _liveMyPosition = point;
      _liveSpeedKmh = smoothedSpeedKmh;
      if (position.heading.isFinite && position.heading >= 0) {
        _liveHeading = position.heading;
      }
    });

    final currentZoom = _mapController.camera.zoom;
    _mapController.move(point, currentZoom < 15 ? 17 : currentZoom);

    final route = _route;
    if (route == null || route.points.isEmpty) return;

    _advanceNavigationStep(point, route);
    _maybeAnnounceUpcomingStep();

    final share = _activeShare;
    if (share != null) {
      _tripShareService.updatePosition(
        share.id,
        position: point,
        headingDeg: _liveHeading,
        speedKmh: _liveSpeedKmh,
        etaSeconds: _estimateEtaSeconds(point, route),
      );
    }

    const offRouteThresholdMeters = 45.0;
    final distanceOffRoute = NavigationGeometry.distanceToRoute(point, route.points);
    final now = DateTime.now();
    final canReroute = !_rerouting &&
        (_lastRerouteAt == null ||
            now.difference(_lastRerouteAt!) > const Duration(seconds: 15));
    if (distanceOffRoute > offRouteThresholdMeters && canReroute) {
      _rerouteFromPosition(point);
    }
  }

  void _advanceNavigationStep(LatLng point, RouteResult route) {
    if (route.steps.isEmpty) return;
    const arrivalThresholdMeters = 30.0;
    final lastIndex = route.steps.length - 1;
    final index = _navStepIndex.clamp(0, lastIndex);
    final location = route.steps[index].location;
    if (location == null) return;
    final distance = NavigationGeometry.distanceMeters(point, location);
    if (distance < arrivalThresholdMeters) {
      if (index == lastIndex) {
        if (!_arrivedAtDestination) {
          setState(() => _arrivedAtDestination = true);
          _voiceService.speak('You have arrived at your destination.');
        }
      } else {
        setState(() {
          _navStepIndex = index + 1;
          _announcedFarForStep = false;
          _announcedNearForStep = false;
        });
      }
    } else if (_arrivedAtDestination) {
      setState(() => _arrivedAtDestination = false);
    }
  }

  /// Called when the live position has drifted off the current route
  /// line (a missed turn, a wrong-way start, a road closure detour) -
  /// re-requests a route from here through whatever stops are still
  /// ahead, the same way Google Maps re-centers the plan around you.
  Future<void> _rerouteFromPosition(LatLng point) async {
    final remaining = _stops.skip(1).map((s) => s.place).whereType<Place>().toList();
    if (remaining.isEmpty) return;

    setState(() => _rerouting = true);
    _voiceService.speak('Recalculating route.');
    try {
      final currentPlace = Place(
        displayName: 'Current location',
        lat: point.latitude,
        lon: point.longitude,
      );
      final newRoute = await _routingService.getRoute(
        waypoints: [currentPlace, ...remaining],
        mode: _mode,
      );
      if (!mounted) return;
      setState(() {
        _route = newRoute;
        _alternatives = [newRoute];
        _selectedAlternativeIndex = 0;
        _navStepIndex = (newRoute.steps.length > 1) ? 1 : 0;
        _announcedFarForStep = false;
        _announcedNearForStep = false;
        _rerouting = false;
        _lastRerouteAt = DateTime.now();
      });
    } catch (_) {
      // Stay quiet on a failed background reroute - the user is mid-trip;
      // we'll simply try again once they're further off the old route.
      if (!mounted) return;
      setState(() {
        _rerouting = false;
        _lastRerouteAt = DateTime.now();
      });
    }
  }

  /// Speaks a heads-up ~400m before a maneuver, then a closer ~120m
  /// "now" cue - each spoken once per step, tracked by the two flags
  /// reset whenever [_navStepIndex] changes.
  void _maybeAnnounceUpcomingStep() {
    final step = _upcomingStep;
    final distance = _distanceToUpcomingManeuver;
    if (step == null || distance == null) return;
    const farThresholdMeters = 400.0;
    const nearThresholdMeters = 120.0;
    if (!_announcedFarForStep && distance <= farThresholdMeters) {
      _announcedFarForStep = true;
      _voiceService.speak('In ${_roundedDistancePhrase(distance)}, ${step.instruction}.');
    } else if (!_announcedNearForStep && distance <= nearThresholdMeters) {
      _announcedNearForStep = true;
      _voiceService.speak(step.instruction);
    }
  }

  /// Turns a raw meter distance into a spoken-friendly phrase - rounded
  /// to the nearest 50m under a kilometer, and to one decimal of a
  /// kilometer beyond that, the way turn-by-turn voices usually do.
  String _roundedDistancePhrase(double meters) {
    if (meters < 1000) {
      final rounded = (meters / 50).round() * 50;
      return rounded <= 0 ? 'a few meters' : '$rounded meters';
    }
    final km = (meters / 100).round() / 10;
    return '$km kilometers';
  }

  void _toggleVoice() {
    setState(() => _voiceEnabled = !_voiceEnabled);
    _voiceService.setEnabled(_voiceEnabled);
    if (_voiceEnabled) {
      _voiceService.speak('Voice guidance on.');
    }
  }

  /// Downloads every map tile along the current route so the trip stays
  /// browsable with no signal - shows progress in a snackbar and guards
  /// against starting a second download while one is already running.
  Future<void> _downloadOfflineRoute() async {
    final route = _route;
    if (route == null || route.points.isEmpty || _downloadingOffline) return;

    setState(() => _downloadingOffline = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Downloading offline map for this route...'),
        duration: Duration(seconds: 3),
      ),
    );

    _offlineDownloadSub?.cancel();
    final completer = Completer<void>();
    _offlineDownloadSub = OfflineMapsService.downloadRoute(routePoints: route.points).listen(
      (percent) {
        if (percent >= 100 && !completer.isCompleted) completer.complete();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    try {
      await completer.future;
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Offline map saved for this route.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Offline download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingOffline = false);
    }
  }

  // --- Live location sharing / convoy ---

  Future<void> _showShareSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final destinationPlace = _stops.isNotEmpty ? _stops.last.place : null;
        return TripShareSheet(
          shareService: _tripShareService,
          activeShare: _activeShare,
          isOwner: widget.authService.currentUser?.uid == _activeShare?.ownerUid,
          getCurrentPosition: () async {
            if (_liveMyPosition != null) return _liveMyPosition;
            try {
              final position = await _determinePosition();
              return LatLng(position.latitude, position.longitude);
            } catch (_) {
              return null;
            }
          },
          destinationLabel: destinationPlace?.displayName,
          destination: destinationPlace != null
              ? LatLng(destinationPlace.lat, destinationPlace.lon)
              : null,
          onShareStarted: _beginWatchingShare,
          onShareEnded: () {
            Navigator.of(sheetContext).pop();
            _stopWatchingShare();
          },
        );
      },
    );
  }

  void _beginWatchingShare(String shareId) {
    _shareSub?.cancel();
    _shareSub = _tripShareService.watch(shareId).listen((share) {
      if (!mounted) return;
      setState(() => _activeShare = share);
    });

    // Keeps a solo "share my location" (or an idle convoy member) live
    // even when not actively navigating - the nav position stream
    // takes over broadcasting, at a much tighter interval, once
    // _startNavigation begins.
    _shareBroadcastTimer?.cancel();
    _shareBroadcastTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _broadcastPositionIfSharing(),
    );
  }

  void _stopWatchingShare() {
    _shareSub?.cancel();
    _shareSub = null;
    _shareBroadcastTimer?.cancel();
    _shareBroadcastTimer = null;
    if (!mounted) return;
    setState(() => _activeShare = null);
  }

  Future<void> _broadcastPositionIfSharing() async {
    final share = _activeShare;
    // While navigating, _handleNavigationPosition already broadcasts on
    // every GPS fix, far more often than this timer - no need to double up.
    if (share == null || _navigating) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      await _tripShareService.updatePosition(
        share.id,
        position: LatLng(position.latitude, position.longitude),
        headingDeg: position.heading.isFinite ? position.heading : null,
        speedKmh: position.speed.isFinite ? position.speed * 3.6 : null,
      );
    } catch (_) {
      // Skip this tick - the next timer fire fifteen seconds from now
      // will simply try again.
    }
  }

  /// A rough remaining-time estimate for sharing with convoy members:
  /// straight-line distance from here to the route's end, divided by
  /// this route's own average pace. Not as precise as the live ETA
  /// Google Maps shows for your own trip, but consistent enough across
  /// everyone in a convoy to answer "who's furthest behind" - which is
  /// the only thing it's used for.
  int? _estimateEtaSeconds(LatLng point, RouteResult route) {
    if (route.points.isEmpty || route.distanceMeters <= 0 || route.durationSeconds <= 0) {
      return null;
    }
    final remainingMeters = NavigationGeometry.distanceMeters(point, route.points.last);
    final avgSpeedMps = route.distanceMeters / route.durationSeconds;
    if (avgSpeedMps <= 0) return null;
    return (remainingMeters / avgSpeedMps).round();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (_screenMode == _ScreenMode.browse && _searchedPlace != null)
        Marker(
          point: LatLng(_searchedPlace!.lat, _searchedPlace!.lon),
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.red, size: 36),
        ),
      if (_screenMode == _ScreenMode.directions)
        for (final entry in _stops.asMap().entries)
          if (entry.value.place != null && !(_navigating && entry.key == 0))
            _markerForStop(entry.key, entry.value.place!),
      if (_navigating && _liveMyPosition != null)
        Marker(
          point: _liveMyPosition!,
          width: 44,
          height: 44,
          child: Transform.rotate(
            angle: (_liveHeading ?? 0) * math.pi / 180,
            child: const Icon(Icons.navigation, color: Colors.blue, size: 36),
          ),
        ),
      if (_activeShare != null && _activeShare!.isConvoy)
        for (final member in _activeShare!.members)
          if (member.uid != widget.authService.currentUser?.uid)
            Marker(
              point: member.position,
              width: 40,
              height: 40,
              child: Tooltip(
                message: member.displayName,
                child: CircleAvatar(
                  backgroundColor: Colors.deepOrange,
                  child: Text(
                    member.displayName.isNotEmpty ? member.displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: _fallbackZoom,
            ),
            children: [
              TileLayer(
                // Plain OSM raster tiles - CARTO's dark basemap now needs
                // a signed-up API key, which isn't worth pulling in just
                // for a dark-mode reskin of the map itself.
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.travel_planner',
                tileProvider: OfflineMapsService.tileProvider(),
              ),
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 5,
                      color: Colors.deepPurple,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // Top bar: a single "search a destination" box in browse mode,
          // or the itinerary bar once directions have started.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _screenMode == _ScreenMode.browse
                  ? _buildBrowseSearchBar()
                  : (_navigating
                      ? NavigationHud(
                          upcomingStep: _upcomingStep,
                          distanceToManeuverMeters: _distanceToUpcomingManeuver,
                          rerouting: _rerouting,
                          arrived: _arrivedAtDestination,
                          onStop: _stopNavigation,
                          voiceEnabled: _voiceEnabled,
                          onToggleVoice: _toggleVoice,
                          onShare: _showShareSheet,
                          sharingActive: _activeShare != null,
                        )
                      : _buildDirectionsBar()),
            ),
          ),

          // Floating "recenter on me" button, like Maps' crosshair FAB.
          Positioned(
            right: 16,
            bottom: (_route != null && !_navigating) ? 260 : 24,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: _loadingLocation ? null : () => _recenterOnMyLocation(),
              child: _loadingLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),

          if (_navigating)
            Positioned(
              left: 16,
              bottom: 24,
              child: Card(
                elevation: 4,
                shape: const CircleBorder(),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _liveSpeedKmh != null ? '${_liveSpeedKmh!.round()}' : '--',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const Text('km/h', style: TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ),

          // Browse mode: once a search result is picked, show its card
          // with a single "Directions" action.
          if (_screenMode == _ScreenMode.browse && _searchedPlace != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: PlaceCard(
                place: _searchedPlace!,
                onDirections: () => _startDirectionsTo(_searchedPlace!),
                onClose: () => setState(() => _searchedPlace = null),
              ),
            ),

          if (_screenMode == _ScreenMode.directions && _route != null && !_navigating)
            RouteInfoPanel(
              route: _route!,
              alternatives: _alternatives,
              selectedIndex: _selectedAlternativeIndex,
              onSelectAlternative: _selectAlternative,
              onClose: () => setState(() => _route = null),
              onStartNavigation: _startNavigation,
              onDownloadOffline: _downloadOfflineRoute,
              downloadingOffline: _downloadingOffline,
              suggestedStops: _suggestedStops,
              onAddComboStop: (stop) => _addPoiAsStop(stop.anchor),
            ),
        ],
      ),
    );
  }

  Marker _markerForStop(int index, Place place) {
    final isFirst = index == 0;
    final isLast = index == _stops.length - 1;
    Widget icon;
    if (isFirst) {
      icon = const Icon(Icons.trip_origin, color: Colors.blue, size: 32);
    } else if (isLast) {
      icon = const Icon(Icons.location_on, color: Colors.red, size: 36);
    } else {
      icon = Container(
        decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          '$index',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }
    return Marker(
      point: LatLng(place.lat, place.lon),
      width: 32,
      height: 32,
      child: icon,
    );
  }

  Widget _buildBrowseSearchBar() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PlaceSearchField(
                    label: 'Search for a place or address',
                    icon: Icons.search,
                    selectedPlace: _searchedPlace,
                    onPlaceSelected: _onSearchResultSelected,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _activeShare != null ? 'Sharing your trip' : 'Share your location',
                  icon: Icon(_activeShare != null ? Icons.groups : Icons.share_location),
                  onPressed: _showShareSheet,
                ),
                const SizedBox(width: 4),
                _buildAccountButton(),
              ],
            ),
            // Only while nothing's picked yet - once a place card is
            // showing at the bottom, these would just be clutter.
            if (_searchedPlace == null) ...[
              const SizedBox(height: 8),
              _buildShortcutsRow(),
            ],
          ],
        ),
      ),
    );
  }

  /// Small avatar button: shows who's signed in (with a sign-out
  /// action), or - for a guest - a way back to the sign-in screen so
  /// Home/Work/recents can start syncing.
  Widget _buildAccountButton() {
    final user = widget.authService.currentUser;
    return IconButton(
      tooltip: user != null
          ? (user.displayName ?? user.email ?? 'Account')
          : 'Sign in to sync your data',
      icon: CircleAvatar(
        radius: 16,
        backgroundImage:
            user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
        child: user?.photoURL == null
            ? Icon(user != null ? Icons.person : Icons.person_outline, size: 18)
            : null,
      ),
      onPressed: _showAccountSheet,
    );
  }

  Future<void> _showAccountSheet() async {
    final user = widget.authService.currentUser;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: user != null
                  ? [
                      Text(
                        user.displayName ?? user.email ?? 'Signed in',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      if (user.email != null)
                        Text(
                          user.email!,
                          style: Theme.of(sheetContext).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Home, Work, and recent searches sync to this account.',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(sheetContext).pop();
                            await widget.authService.signOut();
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign out'),
                        ),
                      ),
                    ]
                  : [
                      Text(
                        'Not signed in',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sign in to sync Home, Work, and recent searches across devices.',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onRequestSignIn == null
                              ? null
                              : () {
                                  Navigator.of(sheetContext).pop();
                                  widget.onRequestSignIn!();
                                },
                          icon: const Icon(Icons.login),
                          label: const Text('Sign in'),
                        ),
                      ),
                    ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShortcutsRow() {
    final chips = <Widget>[
      _buildShortcutChip(
        icon: Icons.explore,
        label: 'Nearby',
        onTap: _showNearbyFromMyLocation,
      ),
      _buildShortcutChip(
        icon: Icons.home,
        label: _home?.displayName ?? 'Set Home',
        onTap: () => _home == null
            ? _promptSetShortcut(isHome: true)
            : _onSearchResultSelected(_home!),
        onLongPress: _home == null ? null : () => _clearShortcut(isHome: true),
      ),
      _buildShortcutChip(
        icon: Icons.work,
        label: _work?.displayName ?? 'Set Work',
        onTap: () => _work == null
            ? _promptSetShortcut(isHome: false)
            : _onSearchResultSelected(_work!),
        onLongPress: _work == null ? null : () => _clearShortcut(isHome: false),
      ),
      if (_recents.isNotEmpty)
        _buildShortcutChip(
          icon: Icons.history,
          label: 'History',
          onTap: _showHistorySheet,
        ),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => chips[index],
      ),
    );
  }

  Widget _buildShortcutChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildDirectionsBar() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _exitDirections,
                  tooltip: 'Back to search',
                ),
                const Expanded(
                  child: Text(
                    'Directions',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            for (final entry in _stops.asMap().entries)
              _buildStopRow(entry.key, entry.value),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _addStop,
                  icon: const Icon(Icons.add),
                  label: const Text('Add stop'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _activeShare != null
                      ? (_activeShare!.isConvoy ? 'Convoy' : 'Sharing your location')
                      : 'Share trip / start convoy',
                  icon: Icon(_activeShare != null ? Icons.groups : Icons.share_location),
                  onPressed: _showShareSheet,
                ),
                TextButton.icon(
                  onPressed: _route == null ? null : _showNearbyAlongRoute,
                  icon: const Icon(Icons.restaurant),
                  label: const Text('Stops on the way'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Own row, alone - so it just centers at its natural width
            // and never competes for horizontal space with anything else
            // (that competition is what caused the overflow).
            Center(
              child: SegmentedButton<TravelMode>(
                segments: const [
                  ButtonSegment(
                    value: TravelMode.driving,
                    icon: Icon(Icons.directions_car),
                  ),
                  ButtonSegment(
                    value: TravelMode.cycling,
                    icon: Icon(Icons.directions_bike),
                  ),
                  ButtonSegment(
                    value: TravelMode.walking,
                    icon: Icon(Icons.directions_walk),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() => _mode = selection.first);
                  _maybeFetchRoute();
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Takes only the space it needs and ellipsizes rather
                // than push the Route button off-screen.
                Expanded(
                  child: _previewLabel(_mode).isEmpty
                      ? const SizedBox.shrink()
                      : Row(
                          children: [
                            Icon(_iconForMode(_mode), size: 18),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _previewLabel(_mode),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loadingRoute ? null : _fetchRoute,
                  icon: _loadingRoute
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.directions),
                  label: const Text('Route'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopRow(int index, _StopEntry stop) {
    final isFirst = index == 0;
    final isLast = index == _stops.length - 1;
    final label = isFirst ? 'From' : (isLast ? 'To' : 'Stop $index');
    final icon = isFirst
        ? Icons.trip_origin
        : (isLast ? Icons.location_on : Icons.add_location_alt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PlaceSearchField(
              key: ValueKey(stop.id),
              label: label,
              icon: icon,
              selectedPlace: stop.place,
              onPlaceSelected: (place) {
                setState(() => stop.place = place);
                _recordRecent(place);
                _maybeFetchRoute();
              },
              onUseCurrentLocation: isFirst
                  ? (_loadingLocation ? null : () => _resolveStopWithMyLocation(stop.id))
                  : null,
            ),
          ),
          if (!isFirst && !isLast)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove stop',
              onPressed: () => _removeStop(stop.id),
            ),
        ],
      ),
    );
  }
}
