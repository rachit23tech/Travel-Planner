import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// One member's live position within a [TripShare] - the other people
/// in a convoy, or (for a solo share) the one person who started it.
class ShareMember {
  final String uid;
  final String displayName;
  final LatLng position;
  final double? headingDeg;
  final double? speedKmh;
  final int? etaSeconds;
  final DateTime? updatedAt;

  const ShareMember({
    required this.uid,
    required this.displayName,
    required this.position,
    this.headingDeg,
    this.speedKmh,
    this.etaSeconds,
    this.updatedAt,
  });

  factory ShareMember.fromMap(String uid, Map<String, dynamic> map) {
    final updatedAtRaw = map['updatedAt'];
    return ShareMember(
      uid: uid,
      displayName: map['displayName'] as String? ?? 'Traveler',
      position: LatLng(
        (map['lat'] as num?)?.toDouble() ?? 0,
        (map['lng'] as num?)?.toDouble() ?? 0,
      ),
      headingDeg: (map['headingDeg'] as num?)?.toDouble(),
      speedKmh: (map['speedKmh'] as num?)?.toDouble(),
      etaSeconds: (map['etaSeconds'] as num?)?.toInt(),
      updatedAt: updatedAtRaw is Timestamp ? updatedAtRaw.toDate() : null,
    );
  }
}

/// A live-sharing session backed by one `shares/{id}` Firestore
/// document - either a one-way "share my location" (`type == 'solo'`,
/// `public == true`, exactly one member: the owner), or a "convoy"
/// (`type == 'convoy'`) where every signed-in member who joined with
/// the share's code sees everyone else live.
class TripShare {
  final String id;
  final String type;
  final String ownerUid;
  final bool active;
  final String? destinationLabel;
  final LatLng? destination;
  final List<ShareMember> members;

  const TripShare({
    required this.id,
    required this.type,
    required this.ownerUid,
    required this.active,
    required this.members,
    this.destinationLabel,
    this.destination,
  });

  bool get isConvoy => type == 'convoy';

  factory TripShare.fromDoc(String id, Map<String, dynamic> data) {
    final membersRaw = data['members'] as Map<String, dynamic>? ?? {};
    final destLat = data['destinationLat'] as num?;
    final destLng = data['destinationLng'] as num?;
    return TripShare(
      id: id,
      type: data['type'] as String? ?? 'solo',
      ownerUid: data['ownerUid'] as String? ?? '',
      active: data['active'] as bool? ?? true,
      destinationLabel: data['destinationLabel'] as String?,
      destination: (destLat != null && destLng != null)
          ? LatLng(destLat.toDouble(), destLng.toDouble())
          : null,
      members: membersRaw.entries
          .map((e) => ShareMember.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList(),
    );
  }
}
