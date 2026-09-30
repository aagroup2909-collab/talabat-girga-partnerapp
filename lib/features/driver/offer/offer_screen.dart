import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../models/models.dart';
import '../../../state/driver.dart';

/// عرض طلب جديد بملء الشاشة مع عدّاد تنازلي.
class OfferScreen extends ConsumerStatefulWidget {
  const OfferScreen({super.key, required this.offer});

  final Offer offer;

  @override
  ConsumerState<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends ConsumerState<OfferScreen> {
  late final Timer _tick;
  late final int _total;
  int _left = 0;
  bool _busy = false;

  Offer get offer => widget.offer;

  @override
  void initState() {
    super.initState();
    _total = offer.secondsLeft.clamp(1, 600);
    _left = _remaining();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final left = _remaining();
      if (left != _left && mounted) setState(() => _left = left);
      if (left <= 0) {
        _tick.cancel();
        ref.read(driverSessionProvider.notifier).expireOffer(offer);
      }
    });
  }

  int _remaining() => offer.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 600);

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final order = await ref.read(driverSessionProvider.notifier).acceptOffer(offer);
      _close();
      router.push('/order/${order.id}');
    } catch (e) {
      // غالبًا العرض انتهى أو أُسند لسائق آخر.
      _close();
      messenger.showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : 'تعذر قبول الطلب.'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    await ref.read(driverSessionProvider.notifier).rejectOffer(offer);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    // لو العرض اختفى (انتهى/اتقبل/اترفض) نقفل الشاشة.
    ref.listen(driverSessionProvider.select((s) => s.offer?.id), (_, id) {
      if (id != offer.id && !_busy) _close();
    });

    final progress = _left / _total;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Text('طلب جديد!', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 20),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                      Center(
                        child: Text('$_left',
                            style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.storefront, color: AppColors.primary, size: 28),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(offer.storeName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                          if (offer.storeAddress?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 36),
                              child: Text(offer.storeAddress!, style: const TextStyle(color: AppColors.muted)),
                            ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(child: _Fact(Icons.near_me_outlined, 'للمتجر', distance(offer.distanceToStoreKm ?? 0))),
                              Expanded(child: _Fact(Icons.route_outlined, 'مسافة التوصيل', distance(offer.deliveryDistanceKm ?? 0))),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: _Fact(Icons.payments_outlined, 'ربحك', money(offer.earning), color: AppColors.success)),
                              Expanded(
                                child: _Fact(
                                  Icons.account_balance_wallet_outlined,
                                  'تحصّل من العميل',
                                  offer.collectAmount > 0 ? money(offer.collectAmount) : 'مدفوع',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.success, textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    onPressed: _busy || _left <= 0 ? null : _accept,
                    child: _busy ? const Spinner() : const Text('قبول الطلب'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : _reject,
                    child: const Text('رفض', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, this.value, {this.color = AppColors.ink});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.muted, size: 22),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
        ],
      );
}
