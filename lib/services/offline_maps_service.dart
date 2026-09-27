import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

/// Wraps flutter_map_tile_caching (FMTC): every tile the map draws is
/// cached to disk automatically, and a whole route's tiles can be
/// pre-downloaded before a trip so the map keeps working with no
/// signal - only the live search/routing/nearby-places calls still
/// need a connection.
class OfflineMapsService {
  static const storeName = 'mapTiles';
  static const tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _userAgent = 'com.example.travel_planner';

  static final _store = FMTCStore(storeName);

  /// Call once, before runApp - sets up the on-disk cache database and
  /// makes sure the store used everywhere else in the app exists.
  static Future<void> initialize() async {
    await FMTCObjectBoxBackend().initialise();
    if (!await _store.manage.ready) {
      await _store.manage.create();
    }
  }

  /// The tile provider every TileLayer in the app should use: it reads
  /// from the cache first and only hits the network for a tile it
  /// hasn't seen (or to refresh a stale one), so ordinary browsing
  /// quietly builds up an offline cache with no extra effort from the
  /// user.
  static FMTCTileProvider tileProvider() {
    return FMTCTileProvider(
      stores: const {storeName: BrowseStoreStrategy.readUpdateCreate},
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
    );
  }

  /// Roughly how many tiles are currently cached - enough for a simple
  /// "X tiles saved for offline use" readout.
  static Future<int> cachedTileCount() => _store.stats.length;

  /// Downloads every tile within [bufferMeters] of the route polyline,
  /// across [minZoom]-[maxZoom], so the whole trip stays browsable with
  /// no signal. Returns a percentage-progress stream (0-100); the
  /// stream closes when the download finishes, fails, or is cancelled
  /// (see [cancelDownload]).
  static Stream<double> downloadRoute({
    required List<LatLng> routePoints,
    double bufferMeters = 1200,
    int minZoom = 12,
    int maxZoom = 16,
  }) {
    final region = LineRegion(routePoints, bufferMeters).toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: TileLayer(
        urlTemplate: tileUrlTemplate,
        userAgentPackageName: _userAgent,
      ),
    );
    final (:downloadProgress, :tileEvents) = _store.download.startForeground(
      region: region,
      skipExistingTiles: true,
      skipSeaTiles: true,
    );
    // We only care about the aggregate percentage for the UI; drain the
    // per-tile event stream so it doesn't build up unread in memory.
    tileEvents.listen((_) {});
    return downloadProgress.map((p) => p.percentageProgress);
  }

  static Future<void> cancelDownload() => _store.download.cancel();
}
