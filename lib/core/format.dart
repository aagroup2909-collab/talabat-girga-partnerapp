import 'package:intl/intl.dart';

// أرقام لاتينية في كل التطبيق (المعتاد في تطبيقات التوصيل المصرية).
final _money = NumberFormat('#,##0.##', 'en');
final _clock = DateFormat('h:mm', 'en');
final _date = DateFormat('d/M', 'en');

/// 120 → "120 ج.م" ، 12.5 → "12.5 ج.م"
String money(num value) => '${_money.format(value)} ج.م';

String qty(num value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();

String timeOfDay(DateTime? t) {
  if (t == null) return '';
  final local = t.toLocal();
  return '${_clock.format(local)} ${local.hour < 12 ? 'ص' : 'م'}';
}

String dateTime(DateTime? t) => t == null ? '' : '${_date.format(t.toLocal())} - ${timeOfDay(t)}';

String distance(num? km) {
  if (km == null) return '';
  return km < 1 ? '${(km * 1000).round()} م' : '${km.toStringAsFixed(1)} كم';
}
