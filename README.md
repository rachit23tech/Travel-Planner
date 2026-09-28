# Iter

*Get there, and everything along the way.*

Iter is an Android travel-planner app built with Flutter: search a destination, plan a multi-stop route, and get live turn-by-turn navigation with voice guidance — plus food, fuel, ATM, pharmacy and restroom stops along the way, and offline maps for when signal drops.

(The Flutter project itself is still named `travel_planner` internally — see [Notes](#notes--known-quirks).)

## Features

- **Search & multi-stop routing** — geocoding via Nominatim, routing via OSRM, with support for multiple stops and alternative routes.
- **Live turn-by-turn navigation** — a navigation HUD with distance-to-maneuver, automatic rerouting when you drift off the route, and spoken voice guidance (heads-up + close-range announcements per step, mute/unmute toggle).
- **Offline maps** — map tiles cache automatically as you browse, and a route's tiles can be pre-downloaded before a trip so the map keeps working with no signal.
- **Stops on the way** — nearby food, fuel, ATMs/banks, and pharmacies via the Geoapify Places API, plus restrooms via public OpenStreetMap Overpass mirrors.
- **Suggested rest stops** — for a drive long enough to need a break, the route preview proactively suggests a combo stop (fuel + food + restroom clustered together) roughly every two hours of driving, instead of waiting for you to think to search.
- **Convoy** — a group of signed-in Iter users heading to the same place can start or join a convoy with a short share code; everyone in it sees the others live on their own map, with a rough ETA for each.
- **Share live location** — share a live-updating link to your location with anyone, through any messaging app (native Android share sheet); the recipient does not need Iter installed, just a browser (see Live location viewer below).
- **Saved places** — home/work shortcuts and recent searches.
- **Accounts & sync** — Google Sign-In via Firebase Auth, with Firestore for cross-device data.
- **Custom brand identity** — a Material 3 theme (Fraunces + Work Sans), generated launcher icon and splash screen.

## Tech stack

- **Flutter / Dart**, targeting Android
- [`flutter_map`](https://pub.dev/packages/flutter_map) + OpenStreetMap raster tiles, with [`flutter_map_tile_caching`](https://pub.dev/packages/flutter_map_tile_caching) for offline tile caching
- **OSRM** for routing, **Nominatim** for geocoding, **Geoapify Places** + **OSM Overpass** for nearby points of interest
- `firebase_core`, `firebase_auth`, `cloud_firestore`, `google_sign_in`
- `flutter_tts` for spoken navigation guidance
- `share_plus` for the native Android share sheet (convoy invites, live-location links)
- Firebase Hosting + the Firestore JS SDK + Leaflet for the anonymous live-location web viewer (`public/live.html`)
- `google_fonts` (Fraunces for display type, Work Sans for body text)
- `flutter_launcher_icons` / `flutter_native_splash` for the generated app icon and splash screen

## Project structure

```
lib/
  main.dart                  # app entrypoint, theme, brand colors
  models/                    # Place, Poi, RouteResult, ComboStop, TripShare
  screens/                   # auth_gate, sign_in_screen, map_screen
  services/                  # auth, geocoding, routing, POIs, saved places,
                              # offline maps, voice guidance, network client,
                              # trip break planning, trip/convoy sharing
  widgets/                   # navigation HUD, route panel, place search,
                              # trip share sheet, etc.
  utils/                     # navigation geometry, maneuver icons, POI styling

public/
  live.html                  # anonymous live-location viewer (Firebase Hosting)
```

## Getting started

### Prerequisites

- Flutter SDK (Dart `>=3.5.0 <4.0.0`)
- Android Studio / Android SDK, plus a device or emulator
- A Firebase project with an Android app registered (for Auth + Firestore), with Hosting enabled too if you want the live-location web viewer to work
- The [Firebase CLI](https://firebase.google.com/docs/cli) (`npm install -g firebase-tools`), for deploying Firestore rules and the Hosting site
- A free [Geoapify](https://www.geoapify.com/) API key (optional, but strongly recommended — see below)

### Setup

1. Clone the repo and fetch packages:

   ```
   flutter pub get
   ```

2. **Firebase**: create a Firebase project, add an Android app with package name `com.example.travel_planner`, then download its `google-services.json` and place it at `android/app/google-services.json`. This file is git-ignored and not included in the repo, so the app won't build without adding your own.

3. **Geoapify**: sign up at [geoapify.com](https://www.geoapify.com/) (free, no card required, 3,000 requests/day), then pass your key at build/run time rather than hardcoding it (this repo is public, and the key would otherwise end up committed):

   ```
   flutter run --dart-define=GEOAPIFY_API_KEY=your_key_here
   ```

   (or add the same `--dart-define` to your IDE's run configuration). Without it, nearby-places search falls back to the public OpenStreetMap Overpass mirrors, which are noticeably less reliable under load.

4. Generate the launcher icon and splash screen (first run only, or after changing the source images in `assets/icon/`):

   ```
   dart run flutter_launcher_icons
   dart run flutter_native_splash:create
   ```

5. Run it:

   ```
   flutter run
   ```

6. **Firestore rules + Hosting** (needed for convoy/live-location sharing to work; the rest of the app works without this step): sign in with the Firebase CLI, then deploy once from the project root:

   ```
   firebase login
   firebase deploy --only firestore:rules,hosting
   ```

   This publishes `firestore.rules` (adds the `shares` collection's rules) and `public/live.html` to Firebase Hosting. Re-run the Hosting half whenever `public/live.html` changes.

### Building a release APK

```
flutter build apk --release --dart-define=GEOAPIFY_API_KEY=your_key_here
```

(omit the `--dart-define` if you are fine with nearby-places search falling back to Overpass for that build.) The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The release build type currently signs with the debug key, so this APK installs fine on any phone for sideloading; add your own signing config in `android/app/build.gradle.kts` before publishing anywhere that requires a proper release signature (e.g. the Play Store).

## Live location viewer

`public/live.html` is a small standalone page (Firestore JS SDK + Leaflet, no build step) that watches a `shares/{id}` Firestore document and updates a map in real time - it is what opens when someone taps a link shared from "Share my live location". It only ever renders a share document marked `public: true` (see `firestore.rules`), which is exactly the kind `TripShareService.startLiveLocationShare` creates; a convoy's document is never public, so a convoy code cannot be used to snoop on it from a browser.

A convoy's join code is itself the access control - anyone who has it can join. That is an intentional, low-stakes trust model (the same one "anyone with the link" sharing uses elsewhere), not a bug; do not rely on it for anything more sensitive than "where is my travel group right now".

## Notes / known quirks

- `compileSdk` is pinned to 36 in `android/app/build.gradle.kts` (and forced onto library subprojects too), because a transitive dependency (`objectbox_flutter_libs`, pulled in by `flutter_map_tile_caching`) requires `compileSdk` 34+ while this project's Flutter install otherwise resolves it lower.
- `flutter_map` is pinned to `^7.0.0`; `flutter_map_tile_caching` is pinned to `^10.0.0` to stay compatible with it, since `flutter_map_tile_caching` 10.1.1+ requires `flutter_map` v8.
- `minSdk` is 23, required by Firebase Auth's Credential Manager / Google Sign-In flow.
