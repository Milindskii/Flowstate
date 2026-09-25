import 'package:flutter/foundation.dart';

/// Available ambient focus soundscapes.
enum SoundscapeTrack {
  none(label: 'Off', icon: 'volume_off'),
  rain(label: 'Soft Rain', icon: 'water_drop'),
  cafe(label: 'Warm Cafe', icon: 'local_cafe'),
  library(label: 'Silent Library', icon: 'menu_book'),
  ocean(label: 'Ocean Waves', icon: 'waves'),
  night(label: 'Night Crickets', icon: 'nights_stay'),
  whiteNoise(label: 'White Noise', icon: 'air');

  final String label;
  final String icon;
  const SoundscapeTrack({required this.label, required this.icon});
}

/// Lightweight ambient sound coordinator for focus rituals.
///
/// Designed with safe zero-dependency execution:
/// Maintains playback state, volume, track selection, and graceful
/// lifecycle teardown without requiring external binary audio codecs or hardware locks.
class FocusSoundscapeService extends ChangeNotifier {
  static final FocusSoundscapeService _instance = FocusSoundscapeService._internal();
  factory FocusSoundscapeService() => _instance;
  FocusSoundscapeService._internal();

  SoundscapeTrack _currentTrack = SoundscapeTrack.none;
  double _volume = 0.6;
  bool _isPlaying = false;

  SoundscapeTrack get currentTrack => _currentTrack;
  double get volume => _volume;
  bool get isPlaying => _isPlaying && _currentTrack != SoundscapeTrack.none;

  void selectTrack(SoundscapeTrack track) {
    if (_currentTrack == track) return;
    _currentTrack = track;
    _isPlaying = track != SoundscapeTrack.none;
    notifyListeners();
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void togglePlayPause() {
    if (_currentTrack == SoundscapeTrack.none) {
      _currentTrack = SoundscapeTrack.rain;
      _isPlaying = true;
    } else {
      _isPlaying = !_isPlaying;
    }
    notifyListeners();
  }

  void stop() {
    if (_isPlaying) {
      _isPlaying = false;
      notifyListeners();
    }
  }

  void reset() {
    _currentTrack = SoundscapeTrack.none;
    _isPlaying = false;
    notifyListeners();
  }
}
