import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks turn-by-turn instructions during live navigation, so the
/// driver doesn't have to glance at the phone to know what's coming up.
/// A thin wrapper around flutter_tts: the rest of the app just calls
/// [speak] with a plain sentence.
class VoiceGuidanceService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool enabled = true;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // Don't block callers waiting for the utterance to finish - lets
      // announcements queue naturally instead of stalling navigation logic.
      await _tts.awaitSpeakCompletion(false);
    } catch (e) {
      debugPrint('VoiceGuidanceService: setup failed: $e');
    }
  }

  /// Speaks [text] aloud, unless voice guidance is currently muted. Safe
  /// to call even if the device has no TTS engine available - failures
  /// are swallowed so a missing voice never breaks navigation itself.
  Future<void> speak(String text) async {
    if (!enabled) return;
    await _ensureInitialized();
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('VoiceGuidanceService: speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing useful to do if even stop() fails.
    }
  }

  void setEnabled(bool value) {
    enabled = value;
    if (!value) stop();
  }

  Future<void> dispose() => stop();
}
