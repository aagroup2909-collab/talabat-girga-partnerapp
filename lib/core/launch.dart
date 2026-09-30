import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// اتصال هاتفي.
Future<void> callPhone(String? phone) async {
  if (phone == null || phone.isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: phone));
}

/// فتح الاتجاهات في خرائط جوجل (التطبيق لو موجود، وإلا المتصفح).
Future<void> navigateTo(LatLng to) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${to.latitude},${to.longitude}&travelmode=driving',
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// واتساب لرقم مصري.
Future<void> openWhatsApp(String phone) async {
  var p = phone.replaceAll(RegExp(r'\D'), '');
  if (p.startsWith('0')) p = '2$p';
  await launchUrl(Uri.parse('https://wa.me/$p'), mode: LaunchMode.externalApplication);
}
