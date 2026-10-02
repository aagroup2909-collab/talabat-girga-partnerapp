import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../services/location_tracker.dart';
import '../services/offer_alert.dart';
import 'auth.dart';

class DriverSession {
  const DriverSession({this.online = false, this.busy = false, this.offer, this.error, this.needsSettings = false});

  final bool online;

  /// جاري تغيير الحالة (زر الاتصال معطل).
  final bool busy;
  final Offer? offer;

  /// آخر رسالة خطأ (مثل تجاوز حد الكاش) — تظهر في الرئيسية.
  final String? error;
  final bool needsSettings;

  DriverSession copyWith({bool? online, bool? busy, Offer? offer, bool clearOffer = false, String? error, bool clearError = false, bool? needsSettings}) =>
      DriverSession(
        online: online ?? this.online,
        busy: busy ?? this.busy,
        offer: clearOffer ? null : (offer ?? this.offer),
        error: clearError ? null : (error ?? this.error),
        needsSettings: needsSettings ?? this.needsSettings,
      );
}

/// حالة السائق أثناء العمل: متصل/غير متصل، إرسال الموقع، واستطلاع العروض.
///
/// لا يوجد WebSockets على السيرفر: العروض كل 5 ثوانٍ والموقع كل 10 ثوانٍ.
class DriverSessionController extends Notifier<DriverSession> {
  Timer? _offerTimer;
  Timer? _locationTimer;
  DateTime? _lastSent;
  bool _polling = false;
  final _rejected = <int>{};

  Repository get _repo => ref.read(repositoryProvider);
  // تُقرأ في build: لا يجوز استخدام ref داخل onDispose (عند الخروج أو تبديل الحساب).
  late LocationTracker _tracker;
  late OfferAlert _alert;

  @override
  DriverSession build() {
    _tracker = ref.watch(locationTrackerProvider);
    _alert = ref.watch(offerAlertProvider);
    ref.onDispose(_stopWork);

    // جلسة جديدة لكل مستخدم (بعد الخروج والدخول بحساب آخر).
    ref.watch(authProvider.select((s) => s.user?.id));

    // لو السيرفر يعتبرنا متصلين (مثلاً التطبيق اتقفل وهو متصل) نكمل العمل.
    final wasOnline = ref.read(authProvider).user?.driver?.isOnline ?? false;
    if (wasOnline) Future.microtask(_resume);
    return DriverSession(online: wasOnline);
  }

  Future<void> _resume() async {
    try {
      await _tracker.ensurePermissions();
      _startWork();
    } on LocationAccessError catch (e) {
      // لا يمكن التتبع → نخرج من الاتصال حتى لا تصل عروض لسائق بدون موقع.
      await _goOfflineQuietly();
      state = state.copyWith(online: false, error: e.message, needsSettings: e.openSettings);
    }
  }

  Future<void> toggle() => state.online ? goOffline() : goOnline();

  Future<void> goOnline() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true, needsSettings: false);
    try {
      await _tracker.ensurePermissions();
      final at = await _tracker.currentPosition();
      await _repo.setOnline(true, at);
      _lastSent = DateTime.now();
      state = state.copyWith(online: true, busy: false);
      _startWork();
    } on LocationAccessError catch (e) {
      state = state.copyWith(busy: false, error: e.message, needsSettings: e.openSettings);
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.fieldError('is_online') ?? e.message);
      if (e.code == 'driver_not_approved') ref.read(authProvider.notifier).refresh().ignore();
    } catch (_) {
      state = state.copyWith(busy: false, error: 'حدث خطأ غير متوقع، حاول مرة أخرى.');
    }
  }

  Future<void> goOffline() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repo.setOnline(false, null);
      await _stopWork();
      state = const DriverSession();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    }
  }

  void clearError() => state = state.copyWith(clearError: true, needsSettings: false);

  Future<void> openSettings() => _tracker.openSettings();

  /// قبول العرض → يرجع الطلب المسند.
  Future<Order> acceptOffer(Offer offer) async {
    try {
      final order = await _repo.acceptOffer(offer.id);
      return order;
    } finally {
      await _dismissOffer();
      ref.invalidate(currentOrdersProvider);
    }
  }

  Future<void> rejectOffer(Offer offer) async {
    _rejected.add(offer.id);
    await _dismissOffer();
    try {
      await _repo.rejectOffer(offer.id);
    } catch (_) {
      // العرض ينتهي تلقائيًا على السيرفر على كل حال.
    }
  }

  /// انتهى وقت العرض على الموبايل.
  Future<void> expireOffer(Offer offer) async {
    if (state.offer?.id != offer.id) return;
    _rejected.add(offer.id);
    await _dismissOffer();
  }

  Future<void> _dismissOffer() async {
    await _alert.stop();
    state = state.copyWith(clearOffer: true);
  }

  void _startWork() {
    _tracker.start(_onPosition);

    _locationTimer?.cancel();
    // نبضة كل 10 ثوانٍ حتى لو السائق واقف (بعض الأجهزة لا ترسل موقعًا بدون حركة).
    _locationTimer = Timer.periodic(AppConfig.locationInterval, (_) {
      final at = _tracker.last;
      if (at != null) _send(at, force: true);
    });

    _offerTimer?.cancel();
    _offerTimer = Timer.periodic(AppConfig.offerPollInterval, (_) => _pollOffer());
    _pollOffer();
  }

  Future<void> _stopWork() async {
    _offerTimer?.cancel();
    _locationTimer?.cancel();
    _offerTimer = _locationTimer = null;
    await _tracker.stop();
    await _alert.stop();
  }

  Future<void> _goOfflineQuietly() async {
    await _stopWork();
    try {
      await _repo.setOnline(false, null);
    } catch (_) {}
  }

  void _onPosition(LatLng at) => _send(at);

  Future<void> _send(LatLng at, {bool force = false}) async {
    final last = _lastSent;
    // الموقع قد يصل أسرع من المطلوب — نحد الإرسال لمرة كل ~10 ثوانٍ.
    if (last != null && DateTime.now().difference(last) < AppConfig.locationInterval - const Duration(seconds: 2)) return;
    _lastSent = DateTime.now();
    try {
      await _repo.sendLocation(at);
    } on ApiException catch (e) {
      _handleWorkError(e);
    } catch (_) {}
  }

  Future<void> _pollOffer() async {
    if (_polling || !state.online) return;
    _polling = true;
    try {
      final offer = await _repo.currentOffer();
      if (!state.online) return;

      if (offer == null || _rejected.contains(offer.id)) {
        if (state.offer != null) await _dismissOffer();
      } else if (state.offer?.id != offer.id) {
        state = state.copyWith(offer: offer);
        await _alert.start(maxDuration: Duration(seconds: offer.secondsLeft + 2));
      }
    } on ApiException catch (e) {
      _handleWorkError(e);
    } catch (_) {
      // انقطاع مؤقت — نحاول في الدورة التالية.
    } finally {
      _polling = false;
    }
  }

  void _handleWorkError(ApiException e) {
    if (e.code == 'driver_not_approved' || e.code == 'driver_profile_required') {
      _stopWork();
      state = DriverSession(error: e.message);
      ref.read(authProvider.notifier).refresh().ignore();
    }
  }
}

final driverSessionProvider = NotifierProvider<DriverSessionController, DriverSession>(DriverSessionController.new);

/// طلبات السائق الجارية — تتحدث كل 10 ثوانٍ طالما في شاشة تعرضها.
final currentOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final timer = Timer(AppConfig.orderPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).currentOrders();
});

final driverOrderProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) async {
  final timer = Timer(AppConfig.orderPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).order(id);
});

final earningsProvider = FutureProvider.autoDispose<Earnings>((ref) => ref.watch(repositoryProvider).earnings());

/// كاش سجّل متجر إنه استلمه من السائق وبانتظار تأكيده — يتحدث كل 30 ثانية أثناء العرض.
final pendingHandoversProvider = FutureProvider.autoDispose<List<SettlementRequest>>((ref) async {
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).pendingHandovers();
});
