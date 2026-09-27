import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place.dart';

/// Persists "Home"/"Work" shortcuts and a short list of recent searches.
///
/// Reads always come from the on-device cache (SharedPreferences), so
/// they're instant and work offline - mirrors the shortcuts Google Maps
/// shows before you've typed anything into its search box. When signed
/// in, every write is also mirrored to this account's Firestore
/// document (`users/{uid}`), fire-and-forget, so Home/Work/recents
/// follow the user to their other devices; [pullFromCloud] is called
/// once right after sign-in to bring that cloud copy down into the
/// local cache.
class SavedPlacesService {
  static const _homeKey = 'saved_place_home';
  static const _workKey = 'saved_place_work';
  static const _recentKey = 'recent_searches';
  static const _maxRecents = 30;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  Future<Place?> getHome() => _getPlace(_homeKey);
  Future<Place?> getWork() => _getPlace(_workKey);

  Future<void> setHome(Place place) async {
    await _setPlace(_homeKey, place);
    unawaited(_userDoc?.set({'home': place.toJson()}, SetOptions(merge: true)));
  }

  Future<void> setWork(Place place) async {
    await _setPlace(_workKey, place);
    unawaited(_userDoc?.set({'work': place.toJson()}, SetOptions(merge: true)));
  }

  Future<void> clearHome() async {
    await _clear(_homeKey);
    unawaited(_userDoc?.set({'home': FieldValue.delete()}, SetOptions(merge: true)));
  }

  Future<void> clearWork() async {
    await _clear(_workKey);
    unawaited(_userDoc?.set({'work': FieldValue.delete()}, SetOptions(merge: true)));
  }

  Future<List<Place>> getRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Place.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Moves [place] to the front of the recent list, de-duplicating by
  /// name + coordinates, capped at [_maxRecents].
  Future<void> addRecent(Place place) async {
    final current = await getRecents();
    current.removeWhere((p) => _samePlace(p, place));
    current.insert(0, place);
    await _saveRecents(current.take(_maxRecents).toList());
  }

  /// Removes one entry from the history (used by the History sheet's
  /// swipe-to-remove).
  Future<void> removeRecent(Place place) async {
    final current = await getRecents();
    current.removeWhere((p) => _samePlace(p, place));
    await _saveRecents(current);
  }

  /// Wipes the whole search history (the History sheet's "Clear all").
  Future<void> clearRecents() async {
    await _saveRecents(const []);
  }

  bool _samePlace(Place a, Place b) =>
      a.displayName == b.displayName && a.lat == b.lat && a.lon == b.lon;

  Future<void> _saveRecents(List<Place> recents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentKey,
      jsonEncode(recents.map((p) => p.toJson()).toList()),
    );
    unawaited(_userDoc?.set(
      {'recents': recents.map((p) => p.toJson()).toList()},
      SetOptions(merge: true),
    ));
  }

  /// Called right after sign-in: pulls this account's Home/Work/recents
  /// down from Firestore and overwrites the local cache with them, so a
  /// returning user sees their synced data immediately. Fails silently
  /// (keeping whatever's already cached locally) if offline or if this
  /// is a brand-new account with nothing saved yet.
  Future<void> pullFromCloud() async {
    final doc = _userDoc;
    if (doc == null) return;
    try {
      final snapshot = await doc.get();
      final data = snapshot.data();
      if (data == null) return;

      final prefs = await SharedPreferences.getInstance();
      final home = data['home'] as Map<String, dynamic>?;
      final work = data['work'] as Map<String, dynamic>?;
      final recents = data['recents'] as List<dynamic>?;

      if (home != null) {
        await prefs.setString(_homeKey, jsonEncode(home));
      }
      if (work != null) {
        await prefs.setString(_workKey, jsonEncode(work));
      }
      if (recents != null) {
        await prefs.setString(_recentKey, jsonEncode(recents));
      }
    } catch (_) {
      // Offline or a Firestore hiccup - the local cache stays as-is.
    }
  }

  Future<Place?> _getPlace(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    return Place.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _setPlace(String key, Place place) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(place.toJson()));
  }

  Future<void> _clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
