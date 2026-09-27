/// A geocoded place: a name plus coordinates.
///
/// Produced either by a Photon search/reverse-geocode call, or by
/// reading the device's current GPS position.
class Place {
  final String displayName;
  final double lat;
  final double lon;

  const Place({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  /// Parses one GeoJSON Feature from Photon's `/api` or `/reverse`
  /// response (https://photon.komoot.io) into a [Place].
  factory Place.fromPhotonFeature(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final lon = (coordinates[0] as num).toDouble();
    final lat = (coordinates[1] as num).toDouble();

    final properties = feature['properties'] as Map<String, dynamic>? ?? {};
    final parts = <String>[];
    for (final key in ['name', 'street', 'city', 'state', 'country']) {
      final value = properties[key];
      if (value is String && value.isNotEmpty && !parts.contains(value)) {
        parts.add(value);
      }
    }

    return Place(
      displayName: parts.isNotEmpty ? parts.join(', ') : 'Unnamed place',
      lat: lat,
      lon: lon,
    );
  }

  /// For persisting to on-device storage (Home/Work shortcuts, recent
  /// searches) - a plain JSON-able map, not tied to any particular API.
  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'lat': lat,
        'lon': lon,
      };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        displayName: json['displayName'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );

  @override
  String toString() => displayName;
}
