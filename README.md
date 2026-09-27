# Iter

*Get there, and everything along the way.*

Iter is an Android travel-planner app built with Flutter: search a destination, plan a multi-stop route, and get live turn-by-turn navigation with voice guidance — plus food, fuel, ATM, pharmacy and restroom stops along the way, and offline maps for when signal drops.

(The Flutter project itself is still named `travel_planner` internally — see [Notes](#notes--known-quirks).)

## Features

- **Search & multi-stop routing** — geocoding via Nominatim, routing via OSRM, with support for multiple stops and alternative routes.
- **Live turn-by-turn navigation** — a navigation HUD with distance-to-maneuver, automatic rerouting when you drift off the route, and spoken voice guidance (heads-up + close-range announcements per step, mute/unmute toggle).
- **Offline maps** — map tiles cache automatically as you browse, and a route's tiles can be pre-downloaded before a trip so the map keeps working with no signal.
- **Stops on the way** — nearby food, fuel, ATMs/banks, and pharmacies via the Geoapify Places API, plus restrooms via public OpenStreetMap Overpass mirrors.
- **Saved places** — home/work shortcuts and recent searches.
- **Accounts & sync** — Google Sign-In via Firebase Auth, with Firestore for cross-device data.
- **Custom brand identity** — a Material 3 theme (Fraunces + Work Sans), generated launcher icon and splash screen.

## Tech stack

- **Flutter / Dart**, targeting Android
- [`flutter_map`](https://pub.dev/packages/flutter_map) + OpenStreetMap raster tiles, with [`flutter_map_tile_caching`](https://pub.dev/packages/flutter_map_tile_caching) for offline tile caching
- **OSRM** for routing, **Nominatim** for geocoding, **Geoapify Places** + **OSM Overpass** for nearby points of interest
- `firebase_core`, `firebase_auth`, `cloud_firestore`, `google_sign_in`
- `flutter_tts` for spoken navigation guidance
- `google_fonts` (Fraunces for display type, Work Sans for body text)
- `flutter_launcher_icons` / `flutter_native_splash` for the generated app icon and splash screen

## Project structure

```
lib/
  main.dart                  # app entrypoint, theme, brand colors
  models/                    # Place, Poi, RouteResult
  screens/                   # auth_gate, sign_in_screen, map_screen
  services/                  # auth, geocoding, routing, POIs, saved places,
                              # offline maps, voice guidance, network client
  widgets/                   # navigation HUD, route panel, place search, etc.
  utils/                     # navigation geometry, maneuver icons, POI styling
```

## Getting started

### Prerequisites

- Flutter SDK (Dart `>=3.5.0 <4.0.0`)
- Android Studio / Android SDK, plus a device or emulator
- A Firebase project with an Android app registered (for Auth + Firestore)
- A free [Geoapify](https://www.geoapify.com/) API key (optional, but strongly recommended — see below)

### Setup

1. Clone the repo and fetch packages:

   ```
   flutter pub get
   ```

2. **Firebase**: create a Firebase project, add an Android app with package name `com.example.travel_planner`, then download its `google-services.json` and place it at `android/app/google-services.json`. This file is git-ignored and not included in the repo, so the app won't build without adding your own.

3. **Geoapify**: sign up at [geoapify.com](https://www.geoapify.com/) (free, no card required, 3,000 requests/day) and paste your API key into the `geoapifyApiKey` constant in `lib/services/poi_service.dart`. Without a key, nearby-places search falls back to the public OpenStreetMap Overpass mirrors, which are noticeably less reliable under load.

4. Generate the launcher icon and splash screen (first run only, or after changing the source images in `assets/icon/`):

   ```
   dart run flutter_launcher_icons
   dart run flutter_native_splash:create
   ```

5. Run it:

   ```
   flutter run
   ```

### Building a release APK

```
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The release build type currently signs with the debug key, so this APK installs fine on any phone for sideloading; add your own signing config in `android/app/build.gradle.kts` before publishing anywhere that requires a proper release signature (e.g. the Play Store).

## Notes / known quirks

- `compileSdk` is pinned to 36 in `android/app/build.gradle.kts` (and forced onto library subprojects too), because a transitive dependency (`objectbox_flutter_libs`, pulled in by `flutter_map_tile_caching`) requires `compileSdk` 34+ while this project's Flutter install otherwise resolves it lower.
- `flutter_map` is pinned to `^7.0.0`; `flutter_map_tile_caching` is pinned to `^10.0.0` to stay compatible with it, since `flutter_map_tile_caching` 10.1.1+ requires `flutter_map` v8.
- `minSdk` is 23, required by Firebase Auth's Credential Manager / Google Sign-In flow.
