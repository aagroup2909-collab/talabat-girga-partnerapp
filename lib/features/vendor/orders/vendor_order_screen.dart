import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/launch.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/vendor.dart';
import 'order_actions.dart';

/// تفاصيل طلب للتاجر + الإجراء التالي حسب الحالة.
class VendorOrderScreen extends ConsumerStatefulWidget {
  const VendorOrderScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<VendorOrderScreen> createState() => _VendorOrderScreenState();
}

class _VendorOrderScreenState extends ConsumerState<VendorOrderScreen> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(vendorOrderProvider(widget.orderId));
    final order = async.value;
    final canCancel = order != null && order.status.isActive && order.status != OrderStatus.pending;

    return Scaffold(
      appBar: AppBar(
        title: Text(order != null ? 'طلب #${order.number}' : 'الطلب'),
        actions: [
          if (canCancel)
            PopupMenuButton<String>(
              onSelected: (_) => _run(() => rejectOrder(context, ref, order)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cancel', child: Text('إلغاء الطلب', style: TextStyle(color: AppColors.danger))),
              ],
            ),
        ],
      ),
      body: switch (async) {
        AsyncValue(:final value?) => _body(value),
        AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(vendorOrderProvider(widget.orderId))),
        _ => const LoadingView(),
      },
      bottomNavigationBar: order == null ? null : _actions(order),
    );
  }

  Widget? _actions(Order o) {
    final Widget child;
    switch (o.status) {
      case OrderStatus.pending:
        child = Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: _busy ? null : () => _run(() => acceptOrder(context, ref, o)),
                icon: const Icon(Icons.check),
                label: const Text('قبول الطلب'),
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
                onPressed: _busy ? null : () => _run(() => rejectOrder(context, ref, o)),
                child: const Text('رفض'),
              ),
            ),
          ],
        );
      case OrderStatus.accepted:
      case OrderStatus.preparing:
        child = Row(
          children: [
            if (o.status == OrderStatus.accepted) ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _busy ? null : () => _run(() => runOrderAction(context, ref, o, (r) => r.markPreparing(o.id), done: 'بدأ التجهيز')),
                  child: const Text('بدء التجهيز'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _run(() => _ready(o)),
                icon: _busy ? const Spinner() : const Icon(Icons.inventory_2_outlined),
                label: const Text('جاهز للاستلام'),
              ),
            ),
          ],
        );
      case OrderStatus.ready:
        child = _Note(
          icon: Icons.hourglass_top_rounded,
          text: o.driver == null ? 'الطلب جاهز — جاري البحث عن سائق.' : 'الطلب جاهز — السائق ${o.driver!.name ?? ''} في الطريق.',
        );
      case OrderStatus.pickedUp:
        child = const _Note(icon: Icons.delivery_dining, text: 'الطلب مع السائق في الطريق للعميل.');
      case OrderStatus.delivered || OrderStatus.cancelled:
        return null;
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
        child: child,
      ),
    );
  }

  Future<bool> _ready(Order o) => runOrderAction(context, ref, o, (Repository r) => r.markReady(o.id), done: 'الطلب جاهز للاستلام');

  Widget _body(Order o) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(vendorOrderProvider(widget.orderId).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusChip(o.statusLabel.isEmpty ? o.status.label : o.statusLabel, color: statusColor(o.status)),
                      const SizedBox(width: 8),
                      if (o.isLate) const StatusChip('متأخر', color: AppColors.danger),
                      const Spacer(),
                      Text(ago(o.createdAt), style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Line(Icons.person_outline, o.customerName ?? 'العميل'),
                  _Line(Icons.access_time, 'وقت الطلب: ${dateTime(o.createdAt)}'),
                  if (o.prepMinutes != null && o.status != OrderStatus.pending) _Line(Icons.timer_outlined, 'مدة التجهيز: ${o.prepMinutes} دقيقة'),
                  if (o.status == OrderStatus.cancelled && o.cancelReason?.isNotEmpty == true)
                    _Line(Icons.cancel_outlined, 'سبب الإلغاء: ${o.cancelReason}', color: AppColors.danger),
                ],
              ),
            ),
          ),
          if (o.notes?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Card(
              color: AppColors.warning.withValues(alpha: 0.1),
              child: ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined, color: AppColors.warning),
                title: const Text('ملاحظات العميل', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(o.notes!, style: const TextStyle(color: AppColors.ink, fontSize: 15)),
              ),
            ),
          ],
          const SectionTitle('الأصناف'),
          Card(
            child: Column(
              children: [
                for (final (i, item) in o.items.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: Text('${qty(item.quantity)}×', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: item.optionsText.isEmpty && (item.notes?.isEmpty ?? true)
                        ? null
                        : Text([item.optionsText, if (item.notes?.isNotEmpty == true) 'ملاحظة: ${item.notes}']
                            .where((s) => s.isNotEmpty)
                            .join('\n')),
                    trailing: Text(money(item.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('الحساب'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  AmountRow('قيمة الأصناف', o.subtotal, bold: o.status == OrderStatus.cancelled),
                  // الطلب الملغي لا يُحتسب له عمولة ولا صافي.
                  if (o.status != OrderStatus.cancelled) ...[
                    AmountRow('عمولة المنصة', o.commissionAmount, negative: true),
                    const Divider(height: 20),
                    AmountRow('صافي المتجر', o.storeNet, bold: true, color: AppColors.success),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.payments_outlined, size: 18, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(
                        o.paymentMethod == 'cash' ? 'الدفع كاش — السائق يحصّل من العميل' : 'مدفوع أونلاين',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (o.driver != null) ...[
            const SectionTitle('السائق'),
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.delivery_dining, color: Colors.white),
                ),
                title: Text(o.driver!.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  o.driver!.vehicleLabel,
                  o.driver!.plate,
                  if (o.driverArrivedAt != null && o.status != OrderStatus.pickedUp && o.status.isActive) 'وصل المتجر',
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
                trailing: o.driver!.phone?.isNotEmpty == true && o.status.isActive
                    ? IconButton.filledTonal(onPressed: () => callPhone(o.driver!.phone), icon: const Icon(Icons.call))
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text, {this.color = AppColors.ink});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: color))),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      );
}
