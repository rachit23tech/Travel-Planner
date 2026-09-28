import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip_share.dart';

/// Backs both "share my live location" (a public, one-way link anyone
/// can open in a browser - see public/live.html - no Iter install
/// needed) and "convoy" (a group of signed-in Iter users navigating to
/// the same place, each seeing the others live on their own map).
///
/// Both are just one Firestore document under `shares/{shareId}`: solo
/// shares mark themselves `public: true` so the Firestore rules let an
/// anonymous web viewer read them; convoy shares stay gated on being
/// signed in, with the share's random join code as the actual invite.
class TripShareService {
  static const _collection = 'shares';

  /// The web page anyone can open to watch a solo share update live,
  /// no account or app install needed - see public/live.html and
  /// firebase.json. Update this if the project's Hosting site ever
  /// gets a custom domain or a non-default site id.
  static const webBaseUrl = 'https://travel-planner-59ded.web.app';

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String get _displayName {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? user?.email ?? 'A traveler';
  }

  CollectionReference<Map<String, dynamic>> get _shares =>
      FirebaseFirestore.instance.collection(_collection);

  /// Six characters, no `0/O/1/I` - easy to read aloud or copy by hand
  /// as a convoy join code, and just as good as a random share id.
  String _generateId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Map<String, dynamic> _memberEntry(LatLng position) => {
        'displayName': _displayName,
        'lat': position.latitude,
        'lng': position.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Starts a one-way, public "share my live location". Returns the
  /// shareable web link - hand it to [updatePosition] as position
  /// updates come in, and to [end] once the user stops sharing.
  Future<String> startLiveLocationShare({
    required LatLng position,
    String? destinationLabel,
    LatLng? destination,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Sign in to share your location.');
    final id = _generateId();
    await _shares.doc(id).set({
      'type': 'solo',
      'ownerUid': uid,
      'public': true,
      'active': true,
      'memberUids': [uid],
      'destinationLabel': destinationLabel,
      'destinationLat': destination?.latitude,
      'destinationLng': destination?.longitude,
      'createdAt': FieldValue.serverTimestamp(),
      'members': {uid: _memberEntry(position)},
    });
    return '$webBaseUrl/live.html?id=$id';
  }

  /// Starts a convoy and returns its short join code - share it by any
  /// means (the native share sheet, a text, reading it aloud); anyone
  /// who calls [joinConvoy] with it joins the same live session.
  Future<String> startConvoy({
    required LatLng position,
    String? destinationLabel,
    LatLng? destination,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Sign in to start a convoy.');
    final id = _generateId();
    await _shares.doc(id).set({
      'type': 'convoy',
      'ownerUid': uid,
      'public': false,
      'active': true,
      'memberUids': [uid],
      'destinationLabel': destinationLabel,
      'destinationLat': destination?.latitude,
      'destinationLng': destination?.longitude,
      'createdAt': FieldValue.serverTimestamp(),
      'members': {uid: _memberEntry(position)},
    });
    return id;
  }

  /// Joins an existing convoy by its code - throws if the code doesn't
  /// exist or belongs to a solo share rather than a convoy.
  Future<String> joinConvoy(String code, {required LatLng position}) async {
    final uid = _uid;
    if (uid == null) throw Exception('Sign in to join a convoy.');
    final id = code.trim().toUpperCase();
    final doc = _shares.doc(id);
    final snapshot = await doc.get();
    if (!snapshot.exists) throw Exception('No convoy found for that code.');
    final data = snapshot.data()!;
    if (data['type'] != 'convoy') throw Exception('That code is not a convoy.');
    if (data['active'] != true) throw Exception('That convoy has ended.');
    await doc.update({
      'memberUids': FieldValue.arrayUnion([uid]),
      'members.$uid': _memberEntry(position),
    });
    return id;
  }

  /// Called on every navigation position update while a share/convoy
  /// is active - cheap merge-only writes, safe to call often. Failures
  /// are swallowed: a missed update mid-trip isn't worth surfacing to
  /// the driver, the next one a few seconds later catches up.
  Future<void> updatePosition(
    String shareId, {
    required LatLng position,
    double? headingDeg,
    double? speedKmh,
    int? etaSeconds,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _shares.doc(shareId).update({
        'members.$uid.lat': position.latitude,
        'members.$uid.lng': position.longitude,
        'members.$uid.updatedAt': FieldValue.serverTimestamp(),
        if (headingDeg != null) 'members.$uid.headingDeg': headingDeg,
        if (speedKmh != null) 'members.$uid.speedKmh': speedKmh,
        if (etaSeconds != null) 'members.$uid.etaSeconds': etaSeconds,
      });
    } catch (_) {
      // See doc comment - silently skip, the next update will catch up.
    }
  }

  /// Live updates for one share/convoy - null once the document is
  /// deleted or (per the security rules) no longer readable by this
  /// user, e.g. a convoy they've left.
  Stream<TripShare?> watch(String shareId) {
    return _shares.doc(shareId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return TripShare.fromDoc(snap.id, data);
    });
  }

  Future<void> leave(String shareId) async {
    final uid = _uid;
    if (uid == null) return;
    await _shares.doc(shareId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
      'members.$uid': FieldValue.delete(),
    });
  }

  /// Marks the share inactive so the web viewer (or other convoy
  /// members) know it's over, without needing delete permission. The
  /// app only offers this to the share's owner (see TripShareSheet);
  /// the security rules allow any current member to call it too, since
  /// nothing sensitive hinges on which member ends a live-location
  /// share.
  Future<void> end(String shareId) async {
    await _shares.doc(shareId).update({'active': false});
  }
}
