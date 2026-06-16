import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// Plays short cues for sent/received messages. Failures are swallowed —
/// audio is a nicety, never a blocker.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final _sentPlayer = AudioPlayer();
  final _recvPlayer = AudioPlayer();

  Future<void> playSent() async {
    try {
      await _sentPlayer.play(AssetSource('sounds/sent.mp3'));
    } catch (_) {}
  }

  Future<void> playReceived() async {
    try {
      await _recvPlayer.play(AssetSource('sounds/received.mp3'));
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 120);
      }
    } catch (_) {}
  }
}