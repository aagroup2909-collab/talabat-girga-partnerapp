import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../state/vendor.dart';

final vendorStoresProvider = FutureProvider.autoDispose<List<StoreSummary>>((ref) => ref.watch(repositoryProvider).vendorStores());

/// "متجري" في شاشة الحساب + تبديل المتجر لو التاجر عنده أكثر من متجر.
class VendorStoreCard extends ConsumerWidget {
  const VendorStoreCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(vendorStoreProvider).value;
    final stores = ref.watch(vendorStoresProvider).value ?? const <StoreSummary>[];

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: NetImage(store?.logo, width: 44, height: 44, radius: 10),
            title: Text(store?.name ?? 'متجري', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text([store?.typeName, store?.phone].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
            trailing: store == null
                ? null
                : StatusChip(store.approvalLabel, color: store.isApproved ? AppColors.success : AppColors.warning),
          ),
          if (stores.length > 1) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('تبديل المتجر'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _pickStore(context, ref, stores, store?.id),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('الحساب والتسويات'),
            subtitle: const Text('صرف الرصيد، التحويل للمنصة، والكاش من السائقين'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/vendor/finance'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('مواعيد العمل'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/vendor/hours'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('أقسام المنيو'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/vendor/categories'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStore(BuildContext context, WidgetRef ref, List<StoreSummary> stores, int? currentId) async {
    final picked = await showModalBottomSheet<StoreSummary>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in stores)
              ListTile(
                leading: NetImage(s.logo, width: 40, height: 40, radius: 8),
                title: Text(s.name),
                trailing: s.id == currentId ? const Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked.id == currentId) return;

    await ref.read(tokenStoreProvider).saveStoreId(picked.id);
    // كل بيانات التاجر تعتمد على المتجر الحالي.
    ref.invalidate(vendorStoreProvider);
    ref.invalidate(newOrdersProvider);
    ref.invalidate(vendorActiveOrdersProvider);
    ref.invalidate(categoriesProvider);
    if (context.mounted) showMessage(context, 'المتجر الحالي: ${picked.name}');
  }
}
