import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';

/// سجل الطلبات المنتهية (تم التوصيل / ملغي) مع تحميل المزيد.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _items = <Order>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _page = 0;
      _hasMore = true;
    }
    if (!_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(repositoryProvider).history(page: _page + 1);
      setState(() {
        if (reset) _items.clear();
        _items.addAll(res.items);
        _page++;
        _hasMore = res.hasMore;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الطلبات')),
      body: _items.isEmpty
          ? (_error != null
              ? ErrorView(error: _error!, onRetry: () => _load(reset: true))
              : _loading
                  ? const LoadingView()
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: ListView(children: const [
                        SizedBox(height: 120),
                        EmptyView(icon: Icons.receipt_long_outlined, title: 'لا توجد طلبات بعد', subtitle: 'الطلبات اللي توصلها هتظهر هنا.'),
                      ]),
                    ))
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 300) _load();
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => i == _items.length
                      ? const Padding(padding: EdgeInsets.all(16), child: LoadingView())
                      : _HistoryTile(order: _items[i]),
                ),
              ),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final delivered = order.status == OrderStatus.delivered;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            NetImage(order.store?.logo, width: 52, height: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.store?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('#${order.number} · ${dateTime(order.deliveredAt ?? order.createdAt)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  StatusChip(order.statusLabel.isEmpty ? order.status.label : order.statusLabel,
                      color: delivered ? AppColors.success : AppColors.danger),
                ],
              ),
            ),
            if (delivered)
              Text(money(order.driverEarning), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.success)),
          ],
        ),
      ),
    );
  }
}
