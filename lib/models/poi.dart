/// A point of interest found via OpenStreetMap's Overpass API - a food
/// stop, restroom, fuel station, ATM/bank, or pharmacy near a location
/// or along a route.
class Poi {
  final String name;
  final String category;
  final double lat;
  final double lon;

  /// Meters from whatever the search was relative to: straight-line
  /// distance from a point for [PoiService.searchNear], or distance to
  /// the nearest point on the route for [PoiService.searchAlongRoute]
  /// (so a small value there means "right on your way", not "close to
  /// the start").
  final double? distanceMeters;

  const Poi({
    required this.name,
    required this.category,
    required this.lat,
    required this.lon,
    this.distanceMeters,
  });

  Poi withDistance(double meters) => Poi(
        name: name,
        category: category,
        lat: lat,
        lon: lon,
        distanceMeters: meters,
      );
}
