import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../state/auth.dart';

/// needs_profile: الإدارة لم تكمل بيانات السائق أو لم تربط التاجر بمتجر بعد.
class NotReadyScreen extends ConsumerStatefulWidget {
  const NotReadyScreen({super.key});

  @override
  ConsumerState<NotReadyScreen> createState() => _NotReadyScreenState();
}

class _NotReadyScreenState extends ConsumerState<NotReadyScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // ربما أكملت الإدارة الحساب منذ آخر فتح للتطبيق.
    Future.microtask(() => _refresh(silent: true));
  }

  Future<void> _refresh({bool silent = false}) async {
    setState(() => _refreshing = true);
    try {
      final user = await ref.read(authProvider.notifier).refresh();
      if (mounted && !silent && user?.needsProfile == true) showMessage(context, 'الحساب لسه مش جاهز.');
    } catch (e) {
      if (mounted && !silent) showError(context, e);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final config = ref.watch(appConfigProvider).value;
    final phone = (config?['support_phone'] as String?)?.trim() ?? '';
    final whatsapp = (config?['support_whatsapp'] as String?)?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Icon(Icons.pending_actions_rounded, size: 80, color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 20),
            const Text('حسابك لسه مش جاهز، تواصل مع الإدارة',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.4)),
            const SizedBox(height: 8),
            Text(
              user?.isVendor == true ? 'الإدارة لم تربط حسابك بمتجر بعد.' : 'الإدارة لم تكمل بيانات السائق بعد.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 28),
            if (phone.isNotEmpty) ...[
              FilledButton.icon(
                onPressed: () => callPhone(phone),
                icon: const Icon(Icons.call),
                label: Text('اتصل بالإدارة: $phone'),
              ),
              const SizedBox(height: 12),
            ],
            if (whatsapp.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: () => openWhatsApp(whatsapp),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('واتساب'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing ? const Spinner(color: AppColors.primary) : const Icon(Icons.refresh),
              label: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }
}
