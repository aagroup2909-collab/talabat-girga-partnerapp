import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../auth/auth_widgets.dart';

final financeProvider = FutureProvider.autoDispose<FinanceSummary>((ref) => ref.watch(repositoryProvider).finance());

final settlementRequestsProvider =
    FutureProvider.autoDispose<List<SettlementRequest>>((ref) async => (await ref.watch(repositoryProvider).settlementRequests()).items);

final statementProvider = FutureProvider.autoDispose<List<Transaction>>((ref) async => (await ref.watch(repositoryProvider).statement()).items);

/// الحساب مع المنصة: الرصيد، طلب صرف/تسجيل تحويل (بموافقة الإدارة)، واستلام كاش من السائقين (بتأكيد السائق).
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(financeProvider);
    ref.invalidate(settlementRequestsProvider);
    ref.invalidate(statementProvider);
  }

  Future<void> _newRequest(BuildContext context, WidgetRef ref, FinanceSummary f, SettlementKind kind, {FinanceDriver? driver}) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _RequestSheet(summary: f, kind: kind, driver: driver),
    );
    if (created == true) _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(financeProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الحساب والتسويات'),
          bottom: const TabBar(tabs: [Tab(text: 'التسويات'), Tab(text: 'كشف الحساب')]),
        ),
        body: TabBarView(
          children: [
            switch (async) {
              AsyncValue(:final value?) => RefreshIndicator(
                  onRefresh: () async {
                    _refresh(ref);
                    await ref.read(financeProvider.future);
                  },
                  child: _settlements(context, ref, value),
                ),
              AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => _refresh(ref)),
              _ => const LoadingView(),
            },
            const _StatementTab(),
          ],
        ),
      ),
    );
  }

  Widget _settlements(BuildContext context, WidgetRef ref, FinanceSummary f) {
    final owed = f.balance >= 0;
    final requests = ref.watch(settlementRequestsProvider).value ?? const <SettlementRequest>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          color: owed ? AppColors.success : AppColors.danger,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(owed ? 'مستحق لك عند المنصة' : 'مستحق عليك للمنصة', style: const TextStyle(color: Colors.white70)),
                Text(money(f.balance.abs()), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                if (f.pendingPayout > 0 || f.pendingPayment > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    f.pendingPayout > 0 ? 'طلب صرف ${money(f.pendingPayout)} بانتظار الإدارة' : 'تحويل ${money(f.pendingPayment)} بانتظار تأكيد الإدارة',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (owed)
          FilledButton.icon(
            onPressed: f.payoutAvailable >= 1 ? () => _newRequest(context, ref, f, SettlementKind.payoutRequest) : null,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('طلب صرف الرصيد'),
          )
        else
          FilledButton.icon(
            onPressed: f.paymentDue >= 1 ? () => _newRequest(context, ref, f, SettlementKind.paymentReport) : null,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('سجّل تحويل للمنصة'),
          ),
        const SizedBox(height: 6),
        const Text(
          'طلبات الصرف والتحويل لا تؤثر على الرصيد إلا بعد موافقة الإدارة.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 12.5),
        ),
        const SectionTitle('استلام كاش من السائقين'),
        if (f.drivers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا يوجد سائقين وصّلوا طلبات كاش لمتجرك مؤخرًا.', style: TextStyle(color: AppColors.muted)),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, d) in f.drivers.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.delivery_dining, color: Colors.white),
                    ),
                    title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      [
                        'معه ${money(d.cashInHand)}',
                        if (d.suggestedAmount > 0) 'ثمن طلباتك ${money(d.suggestedAmount)}',
                        if (d.pendingAmount > 0) 'بانتظار تأكيده ${money(d.pendingAmount)}',
                      ].join(' · '),
                    ),
                    trailing: FilledButton.tonal(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: d.available >= 1 ? () => _newRequest(context, ref, f, SettlementKind.driverCash, driver: d) : null,
                      child: const Text('استلمت'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'لما تستلم كاش من سائق سجّله هنا، وبعد ما السائق يأكد من تطبيقه المبلغ يتخصم من مستحقاتك ومن اللي على السائق.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ),
        const SectionTitle('آخر الطلبات'),
        if (requests.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('لا توجد طلبات تسوية بعد.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          )
        else
          for (final r in requests) Padding(padding: const EdgeInsets.only(bottom: 8), child: _RequestTile(request: r, onChanged: () => _refresh(ref))),
      ],
    );
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.request, required this.onChanged});

  final SettlementRequest request;
  final VoidCallback onChanged;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء الطلب')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).cancelSettlementRequest(request.id);
      onChanged();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final color = switch (r.status) {
      'pending' => AppColors.warning,
      'approved' => AppColors.success,
      'rejected' => AppColors.danger,
      _ => AppColors.muted,
    };
    final waitingFor = r.kind == SettlementKind.driverCash ? 'بانتظار تأكيد السائق' : 'بانتظار الإدارة';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(r.kindLabel, style: const TextStyle(fontWeight: FontWeight.w800))),
                Text(money(r.amount), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (r.driverName != null) 'السائق: ${r.driverName}',
                r.methodLabel,
                if (r.reference?.isNotEmpty == true) 'مرجع ${r.reference}',
                dateTime(r.createdAt),
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                StatusChip(r.isPending ? waitingFor : r.statusLabel, color: color),
                const Spacer(),
                if (r.isPending)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 32)),
                    onPressed: () => _cancel(context, ref),
                    child: const Text('إلغاء'),
                  ),
              ],
            ),
            if (r.rejectionReason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('السبب: ${r.rejectionReason}', style: const TextStyle(color: AppColors.danger)),
              ),
          ],
        ),
      ),
    );
  }
}

/// نموذج طلب تسوية.
class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.summary, required this.kind, this.driver});

  final FinanceSummary summary;
  final SettlementKind kind;
  final FinanceDriver? driver;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  late final _amount = TextEditingController(text: _fmt(_suggested));
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String? _method;
  String? _receiptPath;
  Map<String, String> _errors = {};
  bool _busy = false;

  double get _max => switch (widget.kind) {
        SettlementKind.payoutRequest => widget.summary.payoutAvailable,
        SettlementKind.paymentReport => widget.summary.paymentDue,
        SettlementKind.driverCash => widget.driver!.available,
      };

  double get _suggested => switch (widget.kind) {
        SettlementKind.driverCash => widget.driver!.suggestedAmount > 0 ? widget.driver!.suggestedAmount.clamp(0, _max).toDouble() : _max,
        _ => _max,
      };

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 80);
    if (file != null) setState(() => _receiptPath = file.path);
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text);
    final errors = <String, String>{};
    if (amount == null || amount < 1) {
      errors['amount'] = 'اكتب المبلغ.';
    } else if (amount > _max + 0.001) {
      errors['amount'] = 'أقصى مبلغ ${money(_max)}.';
    }
    if (widget.kind == SettlementKind.paymentReport && _method == null) errors['method'] = 'اختر طريقة التحويل.';
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).createSettlementRequest(
            kind: widget.kind,
            amount: amount!,
            driverId: widget.driver?.id,
            method: _method,
            reference: _reference.text.trim(),
            notes: _notes.text.trim(),
            receiptPath: _receiptPath,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(
        content: Text(widget.kind == SettlementKind.driverCash ? 'تم التسجيل — بانتظار تأكيد السائق.' : 'تم إرسال الطلب للإدارة.'),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      final server = {for (final f in ['amount', 'method', 'driver_id', 'reference', 'receipt']) if (e.fieldError(f) != null) f: e.fieldError(f)!};
      if (server.isEmpty) showError(context, e);
      setState(() => _errors = server);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, hint) = switch (widget.kind) {
      SettlementKind.payoutRequest => ('طلب صرف الرصيد', 'الإدارة هتحوّل لك المبلغ وتأكد الطلب. اختار الطريقة اللي تحب تستلم بيها.'),
      SettlementKind.paymentReport => ('تحويل للمنصة', 'سجّل التحويل اللي عملته للمنصة مع رقم العملية أو صورة الإيصال، والإدارة هتأكده.'),
      SettlementKind.driverCash => ('استلمت كاش من ${widget.driver!.name}', 'السائق هيأكد من تطبيقه إنه سلّمك المبلغ ده.'),
    };

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
              Text(hint, style: const TextStyle(color: AppColors.muted)),
              const FieldLabel('المبلغ'),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                decoration: InputDecoration(suffixText: 'ج.م', helperText: 'أقصى مبلغ ${money(_max)}', errorText: _errors['amount']),
              ),
              if (widget.kind != SettlementKind.driverCash) ...[
                FieldLabel(widget.kind == SettlementKind.payoutRequest ? 'تحب تستلم إزاي؟ (اختياري)' : 'حوّلت إزاي؟'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in widget.summary.methods)
                      ChoiceChip(label: Text(m.label), selected: _method == m.value, onSelected: (_) => setState(() => _method = m.value)),
                  ],
                ),
                if (_errors['method'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_errors['method']!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                  ),
              ],
              if (widget.kind == SettlementKind.paymentReport) ...[
                const FieldLabel('رقم العملية (اختياري)'),
                TextField(controller: _reference, decoration: InputDecoration(errorText: _errors['reference'])),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickReceipt,
                  icon: _receiptPath == null
                      ? const Icon(Icons.receipt_long_outlined)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(File(_receiptPath!), width: 28, height: 28, fit: BoxFit.cover),
                        ),
                  label: Text(_receiptPath == null ? 'إرفاق صورة الإيصال' : 'تغيير الصورة'),
                ),
              ],
              const FieldLabel('ملاحظات (اختياري)'),
              TextField(controller: _notes, maxLines: 2),
              const SizedBox(height: 20),
              FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const ButtonSpinner() : const Text('إرسال')),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementTab extends ConsumerWidget {
  const _StatementTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statementProvider);

    return switch (async) {
      AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => ref.refresh(statementProvider.future),
          child: value.isEmpty
              ? ListView(children: const [SizedBox(height: 80), EmptyView(icon: Icons.receipt_long_outlined, title: 'لا توجد حركات بعد')])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final t = value[i];
                    return Card(
                      child: ListTile(
                        title: Text(t.typeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([t.description ?? '', dateTime(t.createdAt)].where((s) => s.isNotEmpty).join('\n')),
                        trailing: Text(
                          '${t.amount >= 0 ? '+' : '-'} ${money(t.amount.abs())}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: t.amount >= 0 ? AppColors.success : AppColors.danger),
                        ),
                      ),
                    );
                  },
                ),
        ),
      AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(statementProvider)),
      _ => const LoadingView(),
    };
  }
}
