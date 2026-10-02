import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../services/offer_alert.dart';
import 'auth.dart';

/// متجر التاجر الحالي + زر الفتح/الإغلاق.
class VendorStoreController extends AsyncNotifier<VendorStore> {
  @override
  Future<VendorStore> build() {
    ref.watch(authProvider.select((s) => s.user?.id));
    return ref.read(repositoryProvider).vendorStore();
  }

  Future<void> setOpen(bool open) async {
    await ref.read(repositoryProvider).setStoreOpen(open);
    // نعيد التحميل لأن "مفتوح الآن" يعتمد على مواعيد العمل أيضًا.
    state = AsyncData(await ref.read(repositoryProvider).vendorStore());
  }
}

final vendorStoreProvider = AsyncNotifierProvider<VendorStoreController, VendorStore>(VendorStoreController.new);

class NewOrdersState {
  const NewOrdersState({this.orders = const [], this.loaded = false, this.muted = const {}, this.error});

  /// الطلبات بانتظار قبول المتجر (الأقدم أولًا).
  final List<Order> orders;
  final bool loaded;

  /// طلبات أوقف التاجر رنينها بدون قبول/رفض.
  final Set<int> muted;
  final Object? error;

  bool get ringing => orders.any((o) => !muted.contains(o.id));
}

/// يستطلع الطلبات الجديدة كل 10 ثوانٍ طالما التاجر داخل التطبيق،
/// ويرن ويهتز حتى يقبل التاجر الطلب أو يرفضه أو يوقف الصوت.
///
/// لا يوجد WebSockets ولا Push بعد، فالتطبيق لازم يكون مفتوحًا أو في الخلفية القريبة.
class NewOrdersWatcher extends Notifier<NewOrdersState> {
  Timer? _timer;
  bool _busy = false;
  late OfferAlert _alert;

  @override
  NewOrdersState build() {
    final user = ref.watch(authProvider.select((s) => s.user));
    _alert = ref.watch(offerAlertProvider);
    ref.onDispose(() {
      _timer?.cancel();
      _alert.stop();
    });

    if (user == null || !user.isVendor || user.needsProfile) return const NewOrdersState();

    _timer = Timer.periodic(AppConfig.orderPollInterval, (_) => refresh());
    Future.microtask(refresh);
    return const NewOrdersState();
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final page = await ref.read(repositoryProvider).vendorOrders('new');
      final ids = page.items.map((o) => o.id).toSet();
      state = NewOrdersState(
        orders: page.items,
        loaded: true,
        // نحتفظ بكتم الطلبات التي ما زالت جديدة فقط.
        muted: state.muted.intersection(ids),
      );
      _syncAlert();
    } catch (e) {
      state = NewOrdersState(orders: state.orders, loaded: state.loaded, muted: state.muted, error: e);
    } finally {
      _busy = false;
    }
  }

  /// إيقاف الرنين للطلبات الحالية (طلب جديد لاحق يرن من جديد).
  void mute() {
    state = NewOrdersState(orders: state.orders, loaded: state.loaded, muted: {...state.muted, ...state.orders.map((o) => o.id)});
    _syncAlert();
  }

  /// بعد قبول/رفض طلب: نشيله فورًا من القائمة ثم نحدّث من السيرفر.
  void handled(int orderId) {
    state = NewOrdersState(
      orders: state.orders.where((o) => o.id != orderId).toList(),
      loaded: state.loaded,
      muted: state.muted,
    );
    _syncAlert();
    refresh();
  }

  void _syncAlert() {
    if (state.ringing) {
      // start يعيد ضبط مؤقت الإيقاف التلقائي — يستمر الرنين مع كل دورة استطلاع.
      _alert.start(maxDuration: AppConfig.orderPollInterval * 3);
    } else {
      _alert.stop();
    }
  }
}

final newOrdersProvider = NotifierProvider<NewOrdersWatcher, NewOrdersState>(NewOrdersWatcher.new);

/// الطلبات الجارية (مقبولة / تجهيز / جاهزة / مع السائق) — تتحدث كل 10 ثوانٍ أثناء العرض.
final vendorActiveOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final timer = Timer(AppConfig.orderPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return (await ref.watch(repositoryProvider).vendorOrders('active')).items;
});

final vendorOrderProvider = FutureProvider.autoDispose.family<Order, int>((ref, id) async {
  final timer = Timer(AppConfig.orderPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(repositoryProvider).vendorOrder(id);
});

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) => ref.watch(repositoryProvider).categories());
