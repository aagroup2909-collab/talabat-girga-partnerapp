import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/launch.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/auth.dart';

/// حساب السائق غير معتمد بعد (403 driver_not_approved): انتظار الموافقة أو سبب الرفض/الإيقاف.
class ApprovalScreen extends ConsumerStatefulWidget {
  const ApprovalScreen({super.key});

  @override
  ConsumerState<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends ConsumerState<ApprovalScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // الحالة قد تكون تغيّرت من لوحة الإدارة.
    Future.microtask(() => _refresh(silent: true));
  }

  Future<void> _refresh({bool silent = false}) async {
    setState(() => _refreshing = true);
    try {
      final user = await ref.read(authProvider.notifier).refresh();
      if (!mounted) return;
      if (user?.driver?.isApproved == true) {
        showMessage(context, 'تم اعتماد حسابك 🎉');
      } else if (!silent) {
        showMessage(context, 'لسه في انتظار موافقة الإدارة.');
      }
    } catch (e) {
      if (mounted && !silent) showError(context, e);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(authProvider).user?.driver;
    final config = ref.watch(appConfigProvider).value;
    final whatsapp = (config?['support_whatsapp'] as String?)?.trim() ?? '';
    final phone = (config?['support_phone'] as String?)?.trim() ?? '';
    final reason = driver?.rejectionReason?.trim() ?? '';

    final (icon, color, title, body) = switch (driver?.approvalStatus ?? ApprovalStatus.pending) {
      ApprovalStatus.rejected => (
          Icons.cancel_outlined,
          AppColors.danger,
          'تم رفض حسابك',
          reason.isNotEmpty ? 'السبب: $reason' : 'تواصل مع الإدارة لمعرفة التفاصيل.',
        ),
      ApprovalStatus.suspended => (
          Icons.block,
          AppColors.danger,
          'حسابك موقوف',
          reason.isNotEmpty ? 'السبب: $reason' : 'تواصل مع الإدارة لمعرفة التفاصيل.',
        ),
      _ => (
          Icons.hourglass_top_rounded,
          AppColors.warning,
          'حسابك قيد المراجعة',
          'في انتظار موافقة الإدارة. أول ما يتم اعتماد حسابك هتقدر تستقبل الطلبات.',
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('حساب السائق'),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(icon, size: 56, color: color),
                    const SizedBox(height: 12),
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(body, style: const TextStyle(color: AppColors.muted, height: 1.5), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _refreshing ? null : _refresh,
                      icon: _refreshing ? const Spinner(color: AppColors.primary) : const Icon(Icons.refresh),
                      label: const Text('تحديث الحالة'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('بياناتي'),
                    subtitle: const Text('بيانات المركبة والمستندات'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push('/driver/info'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('تغيير كلمة المرور'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push('/change-password'),
                  ),
                  if (phone.isNotEmpty) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.support_agent),
                      title: const Text('اتصل بالإدارة'),
                      onTap: () => callPhone(phone),
                    ),
                  ],
                  if (whatsapp.isNotEmpty) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.chat_outlined),
                      title: const Text('واتساب الإدارة'),
                      onTap: () => openWhatsApp(whatsapp),
                    ),
                  ],
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('تذاكر الدعم'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push('/support'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
