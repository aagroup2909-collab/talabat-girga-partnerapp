import 'package:latlong2/latlong.dart';

/// إعدادات التطبيق. غيّر الرابط وقت التشغيل:
/// flutter run --dart-define=API_BASE_URL=http://127.0.0.1:9123/api/v1
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://talabat.ahgroup.online/api/v1',
  );

  /// أصل السيرفر (بدون /api/v1) لتصحيح روابط الصور.
  static final apiOrigin = Uri.parse(apiBaseUrl).origin;

  /// مركز جرجا — يُستخدم لو مفيش صلاحية موقع.
  static const girgaCenter = LatLng(26.3375, 31.8920);

  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const mapUserAgent = 'com.talabatgirga.talabat_girga_partner';

  // السيرفر على استضافة مشتركة بدون WebSockets → استطلاع دوري.
  static const offerPollInterval = Duration(seconds: 5);
  static const orderPollInterval = Duration(seconds: 10);
  static const locationInterval = Duration(seconds: 10);
}

/// السيرفر المحلي يرجع روابط الصور على 127.0.0.1 — المحاكي لا يصل لها،
/// فنحوّلها لنفس أصل الـ API.
String? fixMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
    final origin = Uri.parse(AppConfig.apiOrigin);
    return uri.replace(scheme: origin.scheme, host: origin.host, port: origin.port).toString();
  }
  return url;
}
