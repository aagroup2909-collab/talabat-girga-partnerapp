import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/config.dart';

/// سبب رفض بدء التتبع — الرسالة جاهزة للعرض.
class LocationAccessError implements Exception {
  LocationAccessError(this.message, {this.openSettings = false});
  final String message;

  /// true لو المستخدم لازم يفتح الإعدادات بنفسه (رفض نهائي أو GPS مقفول).
  final bool openSettings;

  @override
  String toString() => message;
}

/// تتبع موقع السائق أثناء الاتصال.
///
/// على أندرويد يعمل كخدمة أمامية (Foreground Service) بإشعار ثابت،
/// فيستمر إرسال الموقع والاستطلاع حتى مع قفل الشاشة.
class LocationTracker {
  LocationTracker(this._prefs);

  final SharedPreferences _prefs;
  StreamSubscription<Position>? _sub;
  LatLng? last;

  bool get isRunning => _sub != null;

  /// يطلب الصلاحيات بالترتيب: GPS مفعّل ← صلاحية الموقع ← الإشعارات ← استثناء البطارية (مرة واحدة).
  Future<void> ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationAccessError('شغّل الـ GPS (الموقع) من إعدادات الموبايل عشان تستقبل طلبات.', openSettings: true);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationAccessError('لازم تسمح للتطبيق بالوصول لموقعك عشان تستقبل طلبات.');
    }
    if (permission == LocationPermission.deniedForever || permission == LocationPermission.unableToDetermine) {
      throw LocationAccessError('صلاحية الموقع مرفوضة. افتح الإعدادات واسمح بالموقع للتطبيق.', openSettings: true);
    }

    if (Platform.isAndroid) {
      // إشعار الخدمة الأمامية يحتاج صلاحية الإشعارات من أندرويد 13.
      await ph.Permission.notification.request();

      // شركات مثل ريلمي/شاومي توقف التطبيقات في الخلفية — نطلب الاستثناء مرة واحدة.
      const askedKey = 'asked_battery_optimization';
      if (_prefs.getBool(askedKey) != true) {
        await _prefs.setBool(askedKey, true);
        await ph.Permission.ignoreBatteryOptimizations.request();
      }
    }
  }

  Future<void> openSettings() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Future<LatLng> currentPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return last = LatLng(p.latitude, p.longitude);
    } on TimeoutException {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) throw LocationAccessError('تعذر تحديد موقعك، تأكد إن الـ GPS شغال وحاول تاني.');
      return last = LatLng(p.latitude, p.longitude);
    }
  }

  void start(void Function(LatLng) onPosition) {
    if (_sub != null) return;

    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: AppConfig.locationInterval,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'أنت متصل الآن',
              notificationText: 'طلبات جرجا ترسل موقعك لاستقبال الطلبات.',
              notificationChannelName: 'حالة الاتصال',
              notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
            pauseLocationUpdatesAutomatically: false,
          );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        last = LatLng(p.latitude, p.longitude);
        onPosition(last!);
      },
      onError: (_) {},
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

final locationTrackerProvider = Provider<LocationTracker>((ref) {
  final tracker = LocationTracker(ref.watch(prefsProvider));
  ref.onDispose(tracker.stop);
  return tracker;
});
