import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/vendor.dart';
import '../../auth/auth_widgets.dart';

/// مواعيد العمل الأسبوعية. المتجر يقفل تلقائيًا خارجها حتى لو زر "مفتوح" شغال.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key});

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  List<StoreHour>? _hours;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final hours = await ref.read(repositoryProvider).storeHours();
      // نبدأ الأسبوع بالسبت كما هو معتاد في مصر.
      hours.sort((a, b) => ((a.dayOfWeek + 1) % 7).compareTo((b.dayOfWeek + 1) % 7));
      if (mounted) setState(() => _hours = hours);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pickTime(StoreHour h, {required bool opening}) async {
    final current = opening ? h.opensAt : h.closesAt;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0),
      helpText: opening ? 'يفتح الساعة' : 'يقفل الساعة',
    );
    if (picked == null) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => opening ? h.opensAt = value : h.closesAt = value);
  }

  /// نسخ مواعيد يوم لكل الأيام المفتوحة.
  void _copyToAll(StoreHour from) {
    setState(() {
      for (final h in _hours!) {
        h.isClosed = from.isClosed;
        h.opensAt = from.opensAt;
        h.closesAt = from.closesAt;
      }
    });
    showMessage(context, 'تم تطبيق مواعيد ${from.dayName} على كل الأيام.');
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveStoreHours(_hours!);
      ref.invalidate(vendorStoreProvider);
      if (!mounted) return;
      showMessage(context, 'تم حفظ مواعيد العمل.');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.elementAtOrNull(1) ?? '00';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m ${h < 12 ? 'ص' : 'م'}';
  }

  @override
  Widget build(BuildContext context) {
    final hours = _hours;

    return Scaffold(
      appBar: AppBar(title: const Text('مواعيد العمل')),
      body: hours == null
          ? (_error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const NoticeBox(
                  icon: Icons.info_outline,
                  text: 'المتجر بيستقبل طلبات في المواعيد دي بس. لو الإغلاق بعد نص الليل (مثلًا 2 ص) اكتبه عادي وهيتحسب لليوم اللي بعده.',
                ),
                const SizedBox(height: 12),
                for (final h in hours)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(h.dayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                const SizedBox(width: 8),
                                if (h.isClosed) const StatusChip('مغلق', color: AppColors.danger),
                                const Spacer(),
                                Switch(value: !h.isClosed, onChanged: (open) => setState(() => h.isClosed = !open)),
                                PopupMenuButton<String>(
                                  onSelected: (_) => _copyToAll(h),
                                  itemBuilder: (_) => const [PopupMenuItem(value: 'copy', child: Text('تطبيق على كل الأيام'))],
                                ),
                              ],
                            ),
                            if (!h.isClosed)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: Row(
                                  children: [
                                    const Text('من', style: TextStyle(color: AppColors.muted)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _TimeButton(label: _label(h.opensAt), onTap: () => _pickTime(h, opening: true))),
                                    const SizedBox(width: 12),
                                    const Text('إلى', style: TextStyle(color: AppColors.muted)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _TimeButton(label: _label(h.closesAt), onTap: () => _pickTime(h, opening: false))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _save, child: _busy ? const ButtonSpinner() : const Text('حفظ المواعيد')),
              ],
            ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 10)),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
