import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/vendor.dart';
import 'order_actions.dart';

/// الطلبات: زر فتح/إغلاق المتجر + جديدة / جارية / السابقة.
class VendorOrdersScreen extends ConsumerWidget {
  const VendorOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(vendorStoreProvider);
    final newOrders = ref.watch(newOrdersProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(store.value?.name ?? 'الطلبات'),
          bottom: TabBar(
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('جديدة'),
                    if (newOrders.orders.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Badge(label: Text('${newOrders.orders.length}'), backgroundColor: AppColors.danger),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'جارية'),
              const Tab(text: 'السابقة'),
            ],
          ),
        ),
        body: Column(
          children: [
            const _StoreSwitch(),
            if (newOrders.ringing) _RingingBanner(count: newOrders.orders.length),
            const Expanded(
              child: TabBarView(children: [_NewOrdersTab(), _ActiveOrdersTab(), _HistoryTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreSwitch extends ConsumerStatefulWidget {
  const _StoreSwitch();

  @override
  ConsumerState<_StoreSwitch> createState() => _StoreSwitchState();
}

class _StoreSwitchState extends ConsumerState<_StoreSwitch> {
  bool _busy = false;

  Future<void> _toggle(VendorStore store, bool open) async {
    if (!open) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إغلاق المتجر مؤقتًا؟'),
          content: const Text('مش هتوصلك طلبات جديدة لحد ما تفتح تاني. الطلبات الحالية مستمرة.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إغلاق')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(vendorStoreProvider.notifier).setOpen(open);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(vendorStoreProvider);
    final store = async.value;

    if (store == null) {
      return async.hasError
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: ErrorView(error: async.error!, onRetry: () => ref.invalidate(vendorStoreProvider)),
            )
          : const LinearProgressIndicator(minHeight: 2);
    }

    final (color, title, subtitle) = !store.isApproved
        ? (AppColors.warning, 'المتجر ${store.approvalLabel}', 'المتجر لا يظهر للعملاء حتى توافق الإدارة.')
        : !store.isOpen
            ? (AppColors.danger, 'المتجر مغلق', 'لا تصلك طلبات جديدة.')
            : store.isOpenNow
                ? (AppColors.success, 'المتجر مفتوح', 'يستقبل الطلبات الآن.')
                : (AppColors.warning, 'خارج مواعيد العمل', 'يفتح تلقائيًا حسب مواعيد العمل.');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16)),
                Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          _busy
              ? const Padding(padding: EdgeInsets.all(12), child: Spinner(color: AppColors.primary))
              : Switch(
                  value: store.isOpen,
                  activeThumbColor: AppColors.success,
                  onChanged: (v) => _toggle(store, v),
                ),
        ],
      ),
    );
  }
}

class _RingingBanner extends ConsumerWidget {
  const _RingingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.notifications_active, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(count == 1 ? 'طلب جديد بانتظار ردك!' : '$count طلبات جديدة بانتظار ردك!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => ref.read(newOrdersProvider.notifier).mute(),
            child: const Text('إيقاف الصوت'),
          ),
        ],
      ),
    );
  }
}

// ---------------- جديدة ----------------

class _NewOrdersTab extends ConsumerWidget {
  const _NewOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(newOrdersProvider);
    final watcher = ref.read(newOrdersProvider.notifier);

    if (!s.loaded) {
      return s.error != null ? ErrorView(error: s.error!, onRetry: watcher.refresh) : const LoadingView();
    }

    return RefreshIndicator(
      onRefresh: watcher.refresh,
      child: s.orders.isEmpty
          ? ListView(children: const [
              SizedBox(height: 80),
              EmptyView(
                icon: Icons.notifications_none_rounded,
                title: 'لا توجد طلبات جديدة',
                subtitle: 'هيرن الموبايل أول ما يوصل طلب. خلي التطبيق مفتوح.',
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: s.orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _NewOrderCard(order: s.orders[i]),
            ),
    );
  }
}

class _NewOrderCard extends ConsumerStatefulWidget {
  const _NewOrderCard({required this.order});

  final Order order;

  @override
  ConsumerState<_NewOrderCard> createState() => _NewOrderCardState();
}

class _NewOrderCardState extends ConsumerState<_NewOrderCard> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
      child: InkWell(
        onTap: () => context.push('/vendor/order/${o.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OrderHeader(order: o),
              const SizedBox(height: 10),
              for (final item in o.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${qty(item.quantity)}× ', style: const TextStyle(fontWeight: FontWeight.w900)),
                    TextSpan(text: item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (item.optionsText.isNotEmpty)
                      TextSpan(text: ' (${item.optionsText})', style: const TextStyle(color: AppColors.muted)),
                    if (item.notes?.isNotEmpty == true)
                      TextSpan(text: ' — ${item.notes}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
                  ])),
                ),
              if (o.notes?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('ملاحظة: ${o.notes}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 12),
              _busy
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  : Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                            onPressed: () => _run(() => acceptOrder(context, ref, o)),
                            icon: const Icon(Icons.check),
                            label: const Text('قبول'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                            ),
                            onPressed: () => _run(() => rejectOrder(context, ref, o)),
                            child: const Text('رفض'),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// رقم الطلب، الوقت، الإجمالي، الدفع.
class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('#${o.number}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              Text(
                [o.customerName, ago(o.createdAt), '${o.itemsCount} صنف'].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(o.subtotal), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(o.paymentMethod == 'cash' ? 'كاش' : 'مدفوع أونلاين', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ),
      ],
    );
  }
}

// ---------------- جارية ----------------

class _ActiveOrdersTab extends ConsumerWidget {
  const _ActiveOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vendorActiveOrdersProvider);

    return switch (async) {
      AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => ref.refresh(vendorActiveOrdersProvider.future),
          child: value.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  EmptyView(icon: Icons.soup_kitchen_outlined, title: 'لا توجد طلبات جارية'),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _ActiveOrderCard(order: value[i]),
                ),
        ),
      AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(vendorActiveOrdersProvider)),
      _ => const LoadingView(),
    };
  }
}

class _ActiveOrderCard extends ConsumerStatefulWidget {
  const _ActiveOrderCard({required this.order});

  final Order order;

  @override
  ConsumerState<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends ConsumerState<_ActiveOrderCard> {
  bool _busy = false;

  Future<void> _run(Future<Order> Function(Repository r) action, String done) async {
    setState(() => _busy = true);
    await runOrderAction(context, ref, widget.order, action, done: done);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final driverText = o.driver != null
        ? (o.status == OrderStatus.pickedUp ? 'مع السائق ${o.driver!.name ?? ''}' : 'السائق: ${o.driver!.name ?? ''}')
        : 'جاري البحث عن سائق';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/vendor/order/${o.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OrderHeader(order: o),
              const SizedBox(height: 10),
              Row(
                children: [
                  StatusChip(o.statusLabel.isEmpty ? o.status.label : o.statusLabel, color: statusColor(o.status)),
                  const SizedBox(width: 8),
                  if (o.isLate) const StatusChip('متأخر', color: AppColors.danger),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.delivery_dining, size: 18, color: o.driver != null ? AppColors.success : AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(driverText,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ),
                ],
              ),
              if (o.status == OrderStatus.accepted || o.status == OrderStatus.preparing) ...[
                const SizedBox(height: 12),
                _busy
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        children: [
                          if (o.status == OrderStatus.accepted) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _run((r) => r.markPreparing(o.id), 'بدأ تجهيز الطلب #${o.number}'),
                                child: const Text('بدء التجهيز'),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                              onPressed: () => _run((r) => r.markReady(o.id), 'الطلب #${o.number} جاهز للاستلام'),
                              child: const Text('جاهز للاستلام'),
                            ),
                          ),
                        ],
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- السابقة ----------------

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
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
      final res = await ref.read(repositoryProvider).vendorOrders('history', page: _page + 1);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(res.items);
        _page++;
        _hasMore = res.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_error != null) return ErrorView(error: _error!, onRetry: () => _load(reset: true));
      if (_loading) return const LoadingView();
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(children: const [
          SizedBox(height: 80),
          EmptyView(icon: Icons.receipt_long_outlined, title: 'لا توجد طلبات سابقة'),
        ]),
      );
    }

    return RefreshIndicator(
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
          itemBuilder: (_, i) {
            if (i == _items.length) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
            final o = _items[i];
            final delivered = o.status == OrderStatus.delivered;
            return Card(
              child: ListTile(
                onTap: () => context.push('/vendor/order/${o.id}'),
                title: Text('#${o.number}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${dateTime(o.createdAt)} · ${o.itemsCount} صنف'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(delivered ? money(o.storeNet) : money(o.subtotal),
                        style: TextStyle(fontWeight: FontWeight.w900, color: delivered ? AppColors.success : AppColors.muted)),
                    StatusChip(o.statusLabel.isEmpty ? o.status.label : o.statusLabel, color: statusColor(o.status)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
