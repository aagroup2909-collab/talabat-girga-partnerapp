import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// يُحقن في main بعد تحميل SharedPreferences.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// خطأ من السيرفر برسالة عربية جاهزة للعرض.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code, this.errors = const {}});

  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, List<String>> errors;

  String? fieldError(String field) => errors[field]?.first;

  factory ApiException.fromDio(DioException e) {
    final res = e.response;
    if (res == null) {
      return ApiException(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'السيرفر لا يستجيب، حاول مرة أخرى.',
        _ => 'تعذر الاتصال بالإنترنت.',
      });
    }

    final data = res.data;
    final errors = <String, List<String>>{};
    String? message;
    String? code;

    if (data is Map) {
      message = data['message'] as String?;
      code = data['code'] as String?;
      final raw = data['errors'];
      if (raw is Map) {
        raw.forEach((k, v) => errors['$k'] = [for (final m in (v as List)) '$m']);
      }
    }

    // في 422 نعرض أول خطأ تفصيلي لأنه أوضح من الرسالة العامة.
    if (errors.isNotEmpty) message = errors.values.first.first;

    // Laravel يرجع رسالة 429 بالإنجليزية ("Too Many Attempts.") — نعرضها بالعربي دائمًا.
    if (res.statusCode == 429) message = 'محاولات كثيرة، انتظر دقيقة ثم حاول مرة أخرى.';

    message ??= switch (res.statusCode) {
      401 => 'انتهت الجلسة، سجّل الدخول مرة أخرى.',
      403 => 'غير مسموح.',
      404 => 'غير موجود.',
      429 => 'محاولات كثيرة، انتظر قليلًا.',
      _ => 'حدث خطأ غير متوقع (${res.statusCode}).',
    };

    return ApiException(message, statusCode: res.statusCode, code: code, errors: errors);
  }

  @override
  String toString() => message;
}

/// مخزن التوكن + إشعار عند انتهاء الجلسة.
class TokenStore {
  TokenStore(this._prefs);

  static const _key = 'auth_token';
  final SharedPreferences _prefs;
  void Function()? onUnauthorized;

  /// 403 بكود driver_not_approved: الحساب لم يعد معتمدًا → نعيد تحميل الحساب.
  void Function()? onNotApproved;

  String? get token => _prefs.getString(_key);
  Future<void> save(String token) => _prefs.setString(_key, token);
  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_storeKey);
  }

  /// التاجر صاحب أكثر من متجر: المتجر المختار يُرسل في هيدر X-Store-Id.
  static const _storeKey = 'vendor_store_id';
  int? get storeId => _prefs.getInt(_storeKey);
  Future<void> saveStoreId(int id) => _prefs.setInt(_storeKey, id);
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore(ref.watch(prefsProvider)));

final dioProvider = Provider<Dio>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json', 'Accept-Language': 'ar'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = tokens.token;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      final storeId = tokens.storeId;
      if (storeId != null && options.path.startsWith('/vendor/')) options.headers['X-Store-Id'] = '$storeId';
      handler.next(options);
    },
    onError: (e, handler) {
      if (e.response?.statusCode == 401 && tokens.token != null) {
        tokens.onUnauthorized?.call();
      }
      final body = e.response?.data;
      if (e.response?.statusCode == 403 && body is Map && body['code'] == 'driver_not_approved') {
        tokens.onNotApproved?.call();
      }
      handler.next(e);
    },
  ));

  return dio;
});

/// غلاف بسيط يحوّل أخطاء Dio إلى ApiException ويرجع JSON.
class Api {
  Api(this._dio);

  final Dio _dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, [Object? body]) => _run(() => _dio.post(path, data: body));

  Future<dynamic> put(String path, [Object? body]) => _run(() => _dio.put(path, data: body));

  Future<dynamic> delete(String path) => _run(() => _dio.delete(path));

  Future<dynamic> _run(Future<Response> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null || v == ''));
}

final apiProvider = Provider<Api>((ref) => Api(ref.watch(dioProvider)));
