import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../models/models.dart';
import '../../../state/auth.dart';
import '../../../state/driver.dart';

class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final session = ref.watch(driverSessionProvider);
    final orders = ref.watch(currentOrdersProvider);
    final earnings = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('أهلًا ${user?.name.split(' ').first ?? ''}')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentOrdersProvider);
          ref.invalidate(earningsProvider);
          await ref.read(currentOrdersProvider.future).catchError((_) => <Order>[]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _OnlineCard(session: session),
            if (session.error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(session: session),
            ],
            const SizedBox(height: 16),
            ...orders.when(
              data: (list) => [
                if (list.isNotEmpty) ...[
                  Text(list.length == 1 ? 'طلبك الحالي' : 'طلباتك الحالية (${list.length})',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  for (final o in list) ...[_ActiveOrderCard(order: o), const SizedBox(height: 10)],
                ] else if (session.online)
                  const _WaitingCard(),
              ],
              loading: () => [if (!orders.hasValue) const Padding(padding: EdgeInsets.all(24), child: LoadingView())],
              error: (e, _) => [ErrorView(error: e, onRetry: () => ref.invalidate(currentOrdersProvider))],
            ),
            const SizedBox(height: 8),
            if (earnings.value case final e?) _TodayCard(earnings: e),
          ],
        ),
      ),
    );
  }
}

class _OnlineCard extends ConsumerWidget {
  const _OnlineCard({required this.session});

  final DriverSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = session.online;
    final color = online ? AppColors.success : AppColors.muted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            GestureDetector(
              onTap: session.busy ? null : () => _toggle(context, ref),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? AppColors.success : AppColors.surface,
                  border: Border.all(color: color, width: 6),
                  boxShadow: [
                    if (online) BoxShadow(color: AppColors.success.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 4),
                  ],
                ),
                alignment: Alignment.center,
                child: session.busy
                    ? CircularProgressIndicator(color: online ? Colors.white : AppColors.primary)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.power_settings_new_rounded, size: 52, color: online ? Colors.white : AppColors.muted),
                          Text(
                            online ? 'متصل' : 'ابدأ',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: online ? Colors.white : AppColors.ink),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              online ? 'أنت متصل وتستقبل الطلبات' : 'أنت غير متصل',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: online ? AppColors.success : AppColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              online ? 'اضغط للخروج من الاتصال' : 'اضغط على الزر لبدء استقبال الطلبات',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(driverSessionProvider.notifier);
    if (session.online) {
      final hasOrders = ref.read(currentOrdersProvider).value?.isNotEmpty ?? false;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إيقاف استقبال الطلبات؟'),
          content: hasOrders ? const Text('معك طلب جاري — أكمله أولًا. موقعك لن يُرسل وأنت غير متصل.') : null,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إيقاف')),
          ],
        ),
      );
      if (ok == true) await notifier.goOffline();
    } else {
      await notifier.goOnline();
    }
  }
}

class _ErrorBanner extends ConsumerWidget {
  const _ErrorBanner({required this.session});

  final DriverSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(session.error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600))),
          if (session.needsSettings)
            TextButton(
              onPressed: () => ref.read(driverSessionProvider.notifier).openSettings(),
              child: const Text('الإعدادات'),
            )
          else
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => ref.read(driverSessionProvider.notifier).clearError(),
            ),
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('في انتظار طلبات…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('سيرن الموبايل عند وصول طلب جديد. خلي التطبيق مفتوح أو في الخلفية.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final step = switch (order.driverStep) {
      0 => 'في الطريق للمتجر',
      1 => 'في المتجر — ${order.status.label}',
      _ => 'في الطريق للعميل',
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      child: InkWell(
        onTap: () => context.push('/order/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(order.store?.name ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  Text('#${order.number}', style: const TextStyle(color: AppColors.muted)),
                ],
              ),
              const SizedBox(height: 6),
              StatusChip(step),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 18, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(order.deliveryAddress ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text(order.collectAmount > 0 ? 'حصّل ${money(order.collectAmount)}' : 'مدفوع أونلاين',
                      style: const TextStyle(fontWeight: FontWeight.w800))),
                  const Text('افتح الطلب', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  const Icon(Icons.chevron_left, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.earnings});

  final Earnings earnings;

  @override
  Widget build(BuildContext context) {
    final ratio = earnings.cashLimit > 0 ? (earnings.cashInHand / earnings.cashLimit).clamp(0.0, 1.0) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _Stat('أرباح اليوم', money(earnings.today.earnings))),
                Expanded(child: _Stat('طلبات اليوم', '${earnings.today.orders}')),
              ],
            ),
            const SizedBox(height: 14),
            Text('الكاش معك: ${money(earnings.cashInHand)} من ${money(earnings.cashLimit)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              color: ratio >= 0.9 ? AppColors.danger : AppColors.primary,
              backgroundColor: AppColors.line,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      );
}
