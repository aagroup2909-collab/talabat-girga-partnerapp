import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../models/models.dart';
import '../../../state/driver.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  int _period = 0;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الأرباح')),
      body: switch (async) {
        AsyncValue(:final value?) => RefreshIndicator(
            onRefresh: () => ref.refresh(earningsProvider.future),
            child: _body(value),
          ),
        AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(earningsProvider)),
        _ => const LoadingView(),
      },
    );
  }

  Widget _body(Earnings e) {
    final period = [e.today, e.week, e.month][_period];
    final ratio = e.cashLimit > 0 ? (e.cashInHand / e.cashLimit).clamp(0.0, 1.0) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('اليوم')),
            ButtonSegment(value: 1, label: Text('الأسبوع')),
            ButtonSegment(value: 2, label: Text('الشهر')),
          ],
          selected: {_period},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _period = s.first),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.primary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('أرباحك', style: TextStyle(color: Colors.white70)),
                      Text(money(period.earnings), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text('${period.orders}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                    const Text('طلب', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الكاش معك', style: TextStyle(color: AppColors.muted)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(e.cashInHand), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('من حد ${money(e.cashLimit)}', style: const TextStyle(color: AppColors.muted)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: ratio,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                  color: ratio >= 0.9 ? AppColors.danger : AppColors.primary,
                  backgroundColor: AppColors.line,
                ),
                if (ratio >= 1) ...[
                  const SizedBox(height: 8),
                  const Text('وصلت للحد الأقصى — ورّد الكاش للمنصة لتستقبل طلبات جديدة.',
                      style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                ],
                const Divider(height: 28),
                Row(
                  children: [
                    const Expanded(child: Text('رصيدك مع المنصة', style: TextStyle(fontWeight: FontWeight.w600))),
                    Text(
                      money(e.balance.abs()),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: e.balance >= 0 ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
                Text(
                  e.balance >= 0 ? 'مستحق لك من المنصة' : 'مطلوب منك توريده للمنصة',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle('آخر الحركات'),
        if (e.transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('لا توجد حركات بعد.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, t) in e.transactions.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text(t.typeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([t.description ?? '', dateTime(t.createdAt)].where((s) => s.isNotEmpty).join('\n')),
                    trailing: Text(
                      '${t.amount >= 0 ? '+' : '-'} ${money(t.amount.abs())}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: t.amount >= 0 ? AppColors.success : AppColors.danger),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
