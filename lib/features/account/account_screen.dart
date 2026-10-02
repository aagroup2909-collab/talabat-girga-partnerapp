import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../state/auth.dart';
import '../../state/driver.dart';
import '../vendor/vendor_store_card.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final driver = user?.driver;
    final config = ref.watch(appConfigProvider).value;
    final supportPhone = (config?['support_phone'] as String?) ?? '';
    final whatsapp = (config?['support_whatsapp'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.primary,
                    backgroundImage: user?.avatar != null ? NetworkImage(user!.avatar!) : null,
                    child: user?.avatar == null ? const Icon(Icons.person, color: Colors.white, size: 32) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Directionality(textDirection: TextDirection.ltr, child: Text(user?.phone ?? '', style: const TextStyle(color: AppColors.muted))),
                        if (driver != null) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusChip(driver.approvalStatus.label, color: driver.isApproved ? AppColors.success : AppColors.warning),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.star_rounded, size: 18, color: AppColors.warning),
                                Text(driver.rating > 0 ? driver.rating.toStringAsFixed(1) : 'جديد'),
                              ]),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (user?.isVendor == true) ...[
            const VendorStoreCard(),
            const SizedBox(height: 16),
          ],
          Card(
            child: Column(
              children: [
                if (driver != null) ...[
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('بياناتي'),
                    subtitle: Text(['بيانات المركبة والمستندات', driver.vehicleType?.label, driver.vehiclePlate]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · ')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push('/driver/info'),
                  ),
                  const Divider(),
                ],
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('تغيير كلمة المرور'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/change-password'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('الدعم والشكاوى'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/support'),
                ),
                if (whatsapp.isNotEmpty) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: const Text('واتساب الدعم'),
                    onTap: () => openWhatsApp(whatsapp),
                  ),
                ],
                if (supportPhone.isNotEmpty) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.support_agent),
                    title: const Text('اتصل بالدعم'),
                    onTap: () => callPhone(supportPhone),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.danger)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('تسجيل الخروج؟'),
                    content: user?.isDriver == true ? const Text('سيتم إيقاف استقبال الطلبات.') : null,
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
                    ],
                  ),
                );
                if (ok != true) return;
                if (user?.isDriver == true && ref.read(driverSessionProvider).online) {
                  await ref.read(driverSessionProvider.notifier).goOffline();
                }
                await ref.read(authProvider.notifier).signOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}
