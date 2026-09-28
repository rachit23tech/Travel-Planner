import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip_share.dart';
import '../services/trip_share_service.dart';

/// Bottom sheet for both "share my live location" (a public web link -
/// see public/live.html - no Iter install needed to view) and "convoy"
/// (a group of signed-in Iter users heading to the same place, each
/// seeing the others live on their own map).
class TripShareSheet extends StatefulWidget {
  final TripShareService shareService;
  final TripShare? activeShare;
  final bool isOwner;
  final Future<LatLng?> Function() getCurrentPosition;
  final String? destinationLabel;
  final LatLng? destination;

  /// Called with the new share/convoy's id once one is started or
  /// joined, so the caller can begin watching it.
  final ValueChanged<String> onShareStarted;
  final VoidCallback onShareEnded;

  const TripShareSheet({
    super.key,
    required this.shareService,
    required this.getCurrentPosition,
    required this.onShareStarted,
    required this.onShareEnded,
    this.activeShare,
    this.isOwner = true,
    this.destinationLabel,
    this.destination,
  });

  @override
  State<TripShareSheet> createState() => _TripShareSheetState();
}

class _TripShareSheetState extends State<TripShareSheet> {
  bool _busy = false;
  String? _error;
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<LatLng> _requirePosition() async {
    final position = await widget.getCurrentPosition();
    if (position == null) throw Exception('Could not get your current location.');
    return position;
  }

  Future<void> _startSolo() async {
    await _run(() async {
      final position = await _requirePosition();
      final link = await widget.shareService.startLiveLocationShare(
        position: position,
        destinationLabel: widget.destinationLabel,
        destination: widget.destination,
      );
      final id = Uri.parse(link).queryParameters['id'];
      if (id != null) widget.onShareStarted(id);
      await SharePlus.instance.share(ShareParams(
        text: "I'm sharing my live location on Iter: $link",
        subject: 'My live location',
      ));
    });
  }

  Future<void> _startConvoy() async {
    await _run(() async {
      final position = await _requirePosition();
      final code = await widget.shareService.startConvoy(
        position: position,
        destinationLabel: widget.destinationLabel,
        destination: widget.destination,
      );
      widget.onShareStarted(code);
      await SharePlus.instance.share(ShareParams(
        text: 'Join my convoy on Iter - open the app, tap Convoy, then Join, and enter code $code',
        subject: 'Join my Iter convoy',
      ));
    });
  }

  Future<void> _joinConvoy() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    await _run(() async {
      final position = await _requirePosition();
      final id = await widget.shareService.joinConvoy(code, position: position);
      widget.onShareStarted(id);
    });
  }

  Future<void> _inviteMore() async {
    final share = widget.activeShare;
    if (share == null) return;
    if (share.isConvoy) {
      await SharePlus.instance.share(ShareParams(
        text: 'Join my convoy on Iter - open the app, tap Convoy, then Join, and enter code ${share.id}',
        subject: 'Join my Iter convoy',
      ));
    } else {
      await SharePlus.instance.share(ShareParams(
        text: "I'm sharing my live location on Iter: ${TripShareService.webBaseUrl}/live.html?id=${share.id}",
        subject: 'My live location',
      ));
    }
  }

  Future<void> _endOrLeave() async {
    final share = widget.activeShare;
    if (share == null) return;
    await _run(() async {
      // The owner marks it inactive too, so the web viewer (or any
      // other convoy member) knows it's over rather than just seeing
      // one person quietly vanish from the member list.
      if (widget.isOwner) {
        await widget.shareService.end(share.id);
      }
      await widget.shareService.leave(share.id);
      widget.onShareEnded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.activeShare;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              share == null ? 'Share your trip' : (share.isConvoy ? 'Convoy' : 'Sharing your location'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            if (share == null) ...[
              const Text(
                "Share a live link anyone can open in a browser, or start a convoy so friends using Iter can see each other on the way.",
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _startSolo,
                  icon: const Icon(Icons.share_location),
                  label: const Text('Share my live location'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _startConvoy,
                  icon: const Icon(Icons.groups),
                  label: const Text('Start a convoy'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Joining a convoy?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: 'Enter code'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _joinConvoy,
                    child: const Text('Join'),
                  ),
                ],
              ),
            ] else ...[
              if (share.isConvoy) ...[
                Text('Join code: ${share.id}', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                ...share.members.map((m) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_pin_circle),
                      title: Text(m.displayName),
                      subtitle: m.etaSeconds != null ? Text('ETA ${(m.etaSeconds! / 60).round()} min') : null,
                    )),
              ] else
                const Text('Anyone with the link can watch your location update live.'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _inviteMore,
                  icon: const Icon(Icons.ios_share),
                  label: Text(share.isConvoy ? 'Invite more people' : 'Share link again'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _busy ? null : _endOrLeave,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(share.isConvoy ? 'Leave convoy' : 'Stop sharing'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
