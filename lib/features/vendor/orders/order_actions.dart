import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/vendor.dart';

/// "منذ 5 د" — عمر الطلب.
String ago(DateTime? t) {
  if (t == null) return '';
  final m = DateTime.now().difference(t.toLocal()).inMinutes;
  if (m < 1) return 'الآن';
  if (m < 60) return 'منذ $m د';
  final h = m ~/ 60;
  return h < 24 ? 'منذ $h س' : 'منذ ${h ~/ 24} يوم';
}

Color statusColor(OrderStatus s) => switch (s) {
      OrderStatus.pending => AppColors.danger,
      OrderStatus.accepted || OrderStatus.preparing => AppColors.warning,
      OrderStatus.ready => AppColors.primary,
      OrderStatus.pickedUp || OrderStatus.delivered => AppColors.success,
      OrderStatus.cancelled => AppColors.muted,
    };

/// تنفيذ إجراء على طلب مع رسالة الخطأ العربية وتحديث القوائم. يرجع true عند النجاح.
Future<bool> runOrderAction(BuildContext context, WidgetRef ref, Order order, Future<Order> Function(Repository r) action,
    {String? done}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action(ref.read(repositoryProvider));
    if (order.status == OrderStatus.pending) ref.read(newOrdersProvider.notifier).handled(order.id);
    ref.invalidate(vendorActiveOrdersProvider);
    ref.invalidate(vendorOrderProvider(order.id));
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    // ربما تغيّرت حالة الطلب (أُلغي تلقائيًا مثلًا) — نحدّث.
    ref.read(newOrdersProvider.notifier).refresh();
    ref.invalidate(vendorOrderProvider(order.id));
    return false;
  }
}

/// قبول طلب: اختيار مدة التجهيز.
Future<bool> acceptOrder(BuildContext context, WidgetRef ref, Order order) async {
  final avg = ref.read(vendorStoreProvider).value?.avgPrepMinutes ?? 20;
  final minutes = await showModalBottomSheet<int>(
    // فوق شريط التبويبات السفلي.
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    builder: (_) => _PrepTimeSheet(initial: order.prepMinutes ?? avg),
  );
  if (minutes == null || !context.mounted) return false;
  return runOrderAction(context, ref, order, (r) => r.acceptOrder(order.id, minutes), done: 'تم قبول الطلب #${order.number}');
}

/// رفض طلب جديد أو إلغاء طلب جارٍ مع السبب.
Future<bool> rejectOrder(BuildContext context, WidgetRef ref, Order order) async {
  final isNew = order.status == OrderStatus.pending;
  final reason = await showModalBottomSheet<String>(
    // فوق شريط التبويبات السفلي.
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReasonSheet(isNew: isNew, withDriver: order.status == OrderStatus.pickedUp),
  );
  if (reason == null || !context.mounted) return false;
  return runOrderAction(context, ref, order, (r) => r.rejectOrder(order.id, reason),
      done: isNew ? 'تم رفض الطلب.' : 'تم إلغاء الطلب.');
}

class _PrepTimeSheet extends StatefulWidget {
  const _PrepTimeSheet({required this.initial});

  final int initial;

  @override
  State<_PrepTimeSheet> createState() => _PrepTimeSheetState();
}

class _PrepTimeSheetState extends State<_PrepTimeSheet> {
  static const _presets = [10, 15, 20, 30, 45, 60];
  late int _minutes = widget.initial.clamp(1, 180);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('الطلب هيجهز في قد إيه؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('العميل يشوف الوقت المتوقع، والسائق يتبعت قبل ما يجهز.', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _minutes < 180 ? () => setState(() => _minutes = (_minutes + 5).clamp(1, 180)) : null,
                  icon: const Icon(Icons.add),
                ),
                SizedBox(
                  width: 130,
                  child: Text('$_minutes دقيقة',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                ),
                IconButton.filledTonal(
                  onPressed: _minutes > 5 ? () => setState(() => _minutes = (_minutes - 5).clamp(1, 180)) : null,
                  icon: const Icon(Icons.remove),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _presets)
                  ChoiceChip(label: Text('$m د'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: () => Navigator.pop(context, _minutes),
              child: const Text('قبول الطلب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({required this.isNew, required this.withDriver});

  final bool isNew;
  final bool withDriver;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  static const _reasons = [
    'منتج أو أكثر غير متوفر',
    'المتجر مشغول جدًا',
    'المتجر على وشك الإغلاق',
    'مشكلة في عنوان التوصيل',
  ];

  final _other = TextEditingController();
  String? _selected;
  String? _error;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _selected == null ? _other.text.trim() : _selected!;
    if (reason.isEmpty) {
      setState(() => _error = 'اختر السبب أو اكتبه.');
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isNew ? 'رفض الطلب' : 'إلغاء الطلب';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                widget.withDriver
                    ? 'الطلب مع السائق الآن. الإلغاء لا يعوّض السائق تلقائيًا — تواصل مع الإدارة للتسوية.'
                    : 'السبب يظهر للعميل.',
                style: TextStyle(color: widget.withDriver ? AppColors.danger : AppColors.muted),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _selected,
                onChanged: (v) => setState(() {
                  _selected = v;
                  _error = null;
                }),
                child: Column(
                  children: [
                    for (final r in _reasons)
                      RadioListTile<String>(value: r, title: Text(r), contentPadding: EdgeInsets.zero),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _other,
                inputFormatters: [LengthLimitingTextInputFormatter(255)],
                decoration: InputDecoration(hintText: 'سبب آخر…', errorText: _error),
                onTap: () => setState(() => _selected = null),
                onChanged: (_) => setState(() {
                  _selected = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: _submit,
                child: Text(title),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
