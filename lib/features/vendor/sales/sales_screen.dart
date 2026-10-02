import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';

enum SalesRange {
  today('اليوم'),
  yesterday('أمس'),
  week('آخر 7 أيام'),
  month('هذا الشهر');

  const SalesRange(this.label);
  final String label;

  (DateTime, DateTime) get dates {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return switch (this) {
      SalesRange.today => (day, day),
      SalesRange.yesterday => (day.subtract(const Duration(days: 1)), day.subtract(const Duration(days: 1))),
      SalesRange.week => (day.subtract(const Duration(days: 6)), day),
      SalesRange.month => (DateTime(now.year, now.month), day),
    };
  }
}

final salesProvider = FutureProvider.autoDispose.family<SalesSummary, SalesRange>((ref, range) {
  final (from, to) = range.dates;
  return ref.watch(repositoryProvider).salesSummary(from: from, to: to);
});

/// ملخص المبيعات: الطلبات، المبيعات، العمولة، الصافي، الرصيد، والأكثر مبيعًا.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  SalesRange _range = SalesRange.today;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(salesProvider(_range));

    return Scaffold(
      appBar: AppBar(title: const Text('المبيعات')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final r in SalesRange.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(label: Text(r.label), selected: _range == r, onSelected: (_) => setState(() => _range = r)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (async) {
              AsyncValue(:final value?) => RefreshIndicator(
                  onRefresh: () => ref.refresh(salesProvider(_range).future),
                  child: _body(value),
                ),
              AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(salesProvider(_range))),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }

  Widget _body(SalesSummary s) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          color: AppColors.primary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('صافي المبيعات', style: TextStyle(color: Colors.white70)),
                Text(money(s.net), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('من الطلبات المسلّمة فقط', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Stat('كل الطلبات', '${s.ordersCount}', Icons.receipt_long_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _Stat('تم التسليم', '${s.deliveredCount}', Icons.check_circle_outline, AppColors.success)),
            const SizedBox(width: 8),
            Expanded(child: _Stat('ملغي', '${s.cancelledCount}', Icons.cancel_outlined, AppColors.danger)),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                AmountRow('المبيعات', s.sales),
                AmountRow('عمولة المنصة', s.commission, negative: true),
                const Divider(height: 20),
                AmountRow('الصافي', s.net, bold: true, color: AppColors.success),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.account_balance_wallet_outlined, color: s.balance >= 0 ? AppColors.success : AppColors.danger),
            title: const Text('رصيدك مع المنصة', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(s.balance >= 0 ? 'مستحق لك من المنصة' : 'مطلوب منك توريده للمنصة'),
            trailing: Text(
              money(s.balance.abs()),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: s.balance >= 0 ? AppColors.success : AppColors.danger),
            ),
          ),
        ),
        const SectionTitle('الأكثر مبيعًا'),
        if (s.topProducts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('لا توجد مبيعات في هذه الفترة.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, p) in s.topProducts.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Text('${i + 1}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${qty(p.quantity)} قطعة'),
                    trailing: Text(money(p.revenue), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon, [this.color = AppColors.ink]);

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
      );
}
