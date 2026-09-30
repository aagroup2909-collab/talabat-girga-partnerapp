import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../state/auth.dart';

/// واجهة التاجر — تُبنى بعد اكتمال واجهة السائق.
class VendorHomeScreen extends ConsumerWidget {
  const VendorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('حساب التاجر'),
        actions: [
          IconButton(
            tooltip: 'تغيير كلمة المرور',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => context.push('/change-password'),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: EmptyView(
        icon: Icons.storefront,
        title: 'أهلًا ${user?.name ?? ''}',
        subtitle: 'واجهة التاجر في التطبيق قيد التجهيز.\nحاليًا يمكنك إدارة متجرك من لوحة التاجر على الويب.',
        action: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(200, 48), foregroundColor: AppColors.ink),
          onPressed: () => context.push('/support'),
          icon: const Icon(Icons.forum_outlined),
          label: const Text('الدعم'),
        ),
      ),
    );
  }
}
