import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

/// صوت عالٍ متكرر + اهتزاز عند وصول عرض أو طلب جديد.
class OfferAlert {
  final _player = FlutterRingtonePlayer();
  Timer? _autoStop;
  bool _playing = false;

  /// [maxDuration] حد أقصى للأمان لو نسينا نوقفه.
  Future<void> start({Duration maxDuration = const Duration(seconds: 60)}) async {
    _autoStop?.cancel();
    _autoStop = Timer(maxDuration, stop);
    if (_playing) return;
    _playing = true;
    try {
      // صوت المنبه: يرن حتى لو الموبايل على الصامت.
      await _player.playAlarm(looping: true, asAlarm: true, volume: 1);
    } catch (_) {}
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: const [0, 700, 500, 700, 500], repeat: 0);
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    _autoStop?.cancel();
    _autoStop = null;
    if (!_playing) return;
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
  }
}

final offerAlertProvider = Provider<OfferAlert>((ref) {
  final alert = OfferAlert();
  ref.onDispose(alert.stop);
  return alert;
});
