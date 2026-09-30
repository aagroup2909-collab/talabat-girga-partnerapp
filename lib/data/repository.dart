import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../models/models.dart';

class LoginResult {
  LoginResult({required this.token, required this.user, required this.needsProfile});
  final String token;
  final User user;
  final bool needsProfile;
}

/// صفحة من نتائج مرقّمة (Laravel paginator).
class Paged<T> {
  Paged({required this.items, required this.hasMore});
  final List<T> items;
  final bool hasMore;
}

/// كل نداءات الـ API الخاصة بتطبيق الشريك (السائق الآن، والتاجر لاحقًا).
class Repository {
  Repository(this._api);

  final Api _api;

  List<Map<String, dynamic>> _data(dynamic res) => (res['data'] as List).cast<Map<String, dynamic>>();

  Paged<T> _paged<T>(dynamic res, T Function(Map<String, dynamic>) parse) {
    final meta = res['meta'] as Map?;
    return Paged(
      items: _data(res).map(parse).toList(),
      hasMore: meta != null && (meta['current_page'] as num) < (meta['last_page'] as num),
    );
  }

  // ---------- عام ----------
  Future<Map<String, dynamic>> config() async => (await _api.get('/config') as Map).cast<String, dynamic>();

  // ---------- الدخول ----------
  /// الحسابات تنشئها الإدارة — التطبيق فيه دخول فقط.
  Future<LoginResult> login(String phone, String password) async {
    final res = await _api.post('/auth/login', {
      'phone': phone,
      'password': password,
      'app': 'partner',
      'device_name': 'partner-app',
    });
    return LoginResult(
      token: res['token'],
      user: User.fromJson(res['user']),
      needsProfile: res['needs_profile'] == true,
    );
  }

  Future<void> changePassword({required String current, required String password}) => _api.post('/me/password', {
        'current_password': current,
        'password': password,
        'password_confirmation': password,
      });

  Future<void> logout() => _api.post('/auth/logout');

  Future<User> me() async => User.fromJson((await _api.get('/me'))['data']);

  // ---------- السائق: بياناتي ----------
  Future<void> saveDriverProfile({
    required String name,
    required VehicleType vehicleType,
    String? plate,
    required String nationalId,
  }) =>
      _api.post('/driver/profile', {
        'name': name,
        'vehicle_type': vehicleType.name,
        'vehicle_plate': plate,
        'national_id': nationalId,
      });

  Future<void> uploadDocument(DocumentType type, String filePath) async {
    final form = FormData.fromMap({
      'type': type.key,
      'file': await MultipartFile.fromFile(filePath, filename: '${type.key}.jpg'),
    });
    await _api.post('/driver/documents', form);
  }

  // ---------- السائق: التشغيل ----------
  Future<bool> setOnline(bool online, LatLng? at) async {
    final res = await _api.post('/driver/status', {
      'is_online': online,
      'lat': at?.latitude,
      'lng': at?.longitude,
    });
    return res['is_online'] == true;
  }

  Future<void> sendLocation(LatLng at) => _api.post('/driver/location', {'lat': at.latitude, 'lng': at.longitude});

  Future<Offer?> currentOffer() async {
    final data = (await _api.get('/driver/offers/current'))['data'];
    return data is Map ? Offer.fromJson(data.cast<String, dynamic>()) : null;
  }

  Future<Order> acceptOffer(int id) async => Order.fromJson((await _api.post('/driver/offers/$id/accept'))['data']);

  Future<void> rejectOffer(int id) => _api.post('/driver/offers/$id/reject');

  Future<List<Order>> currentOrders() async => _data(await _api.get('/driver/orders/current')).map(Order.fromJson).toList();

  Future<Paged<Order>> history({int page = 1}) async =>
      _paged(await _api.get('/driver/orders/history', query: {'page': page}), Order.fromJson);

  Future<Order> order(int id) async => Order.fromJson((await _api.get('/driver/orders/$id'))['data']);

  Future<Order> arrived(int id) async => Order.fromJson((await _api.post('/driver/orders/$id/arrived'))['data']);

  Future<Order> pickedUp(int id) async => Order.fromJson((await _api.post('/driver/orders/$id/picked-up'))['data']);

  Future<Order> delivered(int id, String code) async =>
      Order.fromJson((await _api.post('/driver/orders/$id/delivered', {'delivery_code': code}))['data']);

  Future<Earnings> earnings() async => Earnings.fromJson((await _api.get('/driver/earnings') as Map).cast<String, dynamic>());

  // ---------- الدعم ----------
  Future<Paged<Ticket>> tickets({int page = 1}) async =>
      _paged(await _api.get('/support/tickets', query: {'page': page}), Ticket.fromJson);

  Future<Ticket> ticket(int id) async => Ticket.fromJson((await _api.get('/support/tickets/$id'))['data']);

  Future<Ticket> createTicket({required String subject, required String message, int? orderId}) async =>
      Ticket.fromJson((await _api.post('/support/tickets', {'subject': subject, 'message': message, 'order_id': orderId}))['data']);

  Future<Ticket> replyTicket(int id, String message) async =>
      Ticket.fromJson((await _api.post('/support/tickets/$id/messages', {'message': message}))['data']);
}

final repositoryProvider = Provider<Repository>((ref) => Repository(ref.watch(apiProvider)));

final appConfigProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.watch(repositoryProvider).config());
