import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api.dart';
import '../../../core/config.dart';
import '../../../core/format.dart';
import '../../../core/launch.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../services/location_tracker.dart';
import '../../../state/driver.dart';

/// تنفيذ الطلب: وصلت للمتجر ← استلمت ← سلّمت (بكود التسليم).
class ActiveOrderScreen extends ConsumerStatefulWidget {
  const ActiveOrderScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends ConsumerState<ActiveOrderScreen> {
  bool _busy = false;

  Future<void> _run(Future<Order> Function(Repository repo) action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(repositoryProvider));
      ref.invalidate(driverOrderProvider(widget.orderId));
      ref.invalidate(currentOrdersProvider);
      if (mounted && done != null) showMessage(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver(Order order) async {
    final code = await showDialog<String>(context: context, builder: (_) => _DeliveryCodeDialog(order: order));
    if (code == null || !mounted) return;

    setState(() => _busy = true);
    try {
      // نرسل الموقع الحالي أولًا لأن السيرفر يتحقق من القرب من العميل.
      final tracker = ref.read(locationTrackerProvider);
      try {
        final at = await tracker.currentPosition();
        await ref.read(repositoryProvider).sendLocation(at);
      } catch (_) {}

      await ref.read(repositoryProvider).delivered(order.id, code);
      ref.invalidate(currentOrdersProvider);
      ref.invalidate(earningsProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.success, size: 56),
          title: const Text('تم التسليم بنجاح'),
          content: Text('ربحك من الطلب: ${money(order.driverEarning)}', textAlign: TextAlign.center),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام'))],
        ),
      );
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverOrderProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: Text(async.hasValue ? 'طلب #${async.value!.number}' : 'الطلب')),
      body: switch (async) {
        AsyncValue(:final value?) => _body(value),
        AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(driverOrderProvider(widget.orderId))),
        _ => const LoadingView(),
      },
    );
  }

  Widget _body(Order order) {
    if (order.status == OrderStatus.cancelled) {
      return EmptyView(
        icon: Icons.cancel_outlined,
        title: 'تم إلغاء الطلب',
        subtitle: order.cancelReason,
        action: FilledButton(onPressed: () => context.go('/'), child: const Text('الرئيسية')),
      );
    }
    if (order.status == OrderStatus.delivered) {
      return EmptyView(
        icon: Icons.check_circle_outline,
        title: 'تم توصيل الطلب',
        subtitle: 'ربحك: ${money(order.driverEarning)}',
        action: FilledButton(onPressed: () => context.go('/'), child: const Text('الرئيسية')),
      );
    }

    final step = order.driverStep;
    final storeReady = order.status == OrderStatus.ready;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(height: 220, child: _OrderMap(order: order, towardStore: step < 2)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Steps(step: step),
                    const SizedBox(height: 16),
                    _PartyCard(
                      icon: Icons.storefront,
                      title: order.store?.name ?? 'المتجر',
                      subtitle: order.store?.address,
                      badge: step < 2 ? order.status.label : null,
                      highlighted: step < 2,
                      phone: order.store?.phone,
                      point: order.store?.point,
                    ),
                    const SizedBox(height: 12),
                    _PartyCard(
                      icon: Icons.person_pin_circle_outlined,
                      title: order.customerName ?? 'العميل',
                      subtitle: order.deliveryAddress,
                      highlighted: step == 2,
                      phone: order.customerPhone,
                      point: order.deliveryPoint,
                    ),
                    const SizedBox(height: 12),
                    _MoneyCard(order: order),
                    if (order.notes?.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.sticky_note_2_outlined, color: AppColors.warning),
                          title: const Text('ملاحظات العميل', style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(order.notes!),
                        ),
                      ),
                    ],
                    const SectionTitle('محتويات الطلب'),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, item) in order.items.indexed) ...[
                            if (i > 0) const Divider(),
                            ListTile(
                              dense: true,
                              leading: Text('${qty(item.quantity)}×', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: item.optionsText.isEmpty && (item.notes?.isEmpty ?? true)
                                  ? null
                                  : Text([item.optionsText, item.notes ?? ''].where((s) => s.isNotEmpty).join(' — ')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
            child: switch (step) {
              0 => FilledButton.icon(
                  onPressed: _busy ? null : () => _run((r) => r.arrived(order.id), done: 'تم. استلم الطلب من المتجر.'),
                  icon: _busy ? const Spinner() : const Icon(Icons.storefront),
                  label: const Text('وصلت للمتجر'),
                ),
              1 => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!storeReady)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('المتجر لسه بيجهز الطلب (${order.status.label})',
                            style: const TextStyle(color: AppColors.muted)),
                      ),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _run((r) => r.pickedUp(order.id), done: 'تمام! وصّل الطلب للعميل.'),
                      icon: _busy ? const Spinner() : const Icon(Icons.shopping_bag_outlined),
                      label: const Text('استلمت الطلب'),
                    ),
                  ],
                ),
              _ => FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: _busy ? null : () => _deliver(order),
                  icon: _busy ? const Spinner() : const Icon(Icons.verified_outlined),
                  label: const Text('تم التسليم'),
                ),
            },
          ),
        ),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.step});

  final int step;

  static const _labels = ['للمتجر', 'في المتجر', 'للعميل', 'تم'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(height: 3, color: i <= step ? AppColors.primary : AppColors.line),
            ),
          Column(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: i < step ? AppColors.success : (i == step ? AppColors.primary : AppColors.line),
                child: i < step
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : Text('${i + 1}', style: TextStyle(color: i == step ? Colors.white : AppColors.muted, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Text(_labels[i], style: TextStyle(fontSize: 12, fontWeight: i == step ? FontWeight.w800 : FontWeight.w500)),
            ],
          ),
        ],
      ],
    );
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    this.phone,
    this.point,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final String? phone;
  final LatLng? point;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: highlighted ? AppColors.primary : AppColors.line, width: highlighted ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: highlighted ? AppColors.primary : AppColors.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                if (badge != null) StatusChip(badge!),
              ],
            ),
            if (subtitle?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 32),
                child: Text(subtitle!, style: const TextStyle(color: AppColors.muted)),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: phone == null || phone!.isEmpty ? null : () => callPhone(phone),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('اتصال'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: point == null ? null : () => navigateTo(point!),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('الاتجاهات'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final cash = order.collectAmount > 0;
    return Card(
      color: cash ? AppColors.warning.withValues(alpha: 0.1) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cash ? 'حصّل من العميل' : 'الطلب مدفوع أونلاين', style: const TextStyle(color: AppColors.muted)),
                  Text(cash ? money(order.collectAmount) : 'لا تحصّل شيئًا',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('ربحك', style: TextStyle(color: AppColors.muted)),
                Text(money(order.driverEarning),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.success)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderMap extends ConsumerWidget {
  const _OrderMap({required this.order, required this.towardStore});

  final Order order;
  final bool towardStore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = order.store?.point;
    final home = order.deliveryPoint;
    final me = ref.read(locationTrackerProvider).last;
    final points = [?store, ?home, ?me];
    if (points.isEmpty) return const ColoredBox(color: AppColors.line);

    Marker marker(LatLng p, IconData icon, Color color) => Marker(
          point: p,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        );

    return FlutterMap(
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 14,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48), maxZoom: 16)
            : null,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(urlTemplate: AppConfig.tileUrl, userAgentPackageName: AppConfig.mapUserAgent),
        if (store != null && home != null)
          PolylineLayer(polylines: [
            Polyline(points: [store, home], color: AppColors.primary.withValues(alpha: 0.6), strokeWidth: 3, pattern: StrokePattern.dashed(segments: const [8, 6])),
          ]),
        MarkerLayer(markers: [
          if (store != null) marker(store, Icons.storefront, towardStore ? AppColors.primary : AppColors.ink),
          if (home != null) marker(home, Icons.home_rounded, towardStore ? AppColors.ink : AppColors.success),
          if (me != null) marker(me, Icons.delivery_dining, Colors.blue),
        ]),
      ],
    );
  }
}

class _DeliveryCodeDialog extends StatefulWidget {
  const _DeliveryCodeDialog({required this.order});

  final Order order;

  @override
  State<_DeliveryCodeDialog> createState() => _DeliveryCodeDialogState();
}

class _DeliveryCodeDialogState extends State<_DeliveryCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cash = widget.order.collectAmount;
    return AlertDialog(
      title: const Text('كود التسليم'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('اطلب من العميل كود التسليم (4 أرقام) الظاهر في تطبيقه.', style: TextStyle(color: AppColors.muted)),
          if (cash > 0) ...[
            const SizedBox(height: 8),
            Text('تأكد إنك حصّلت ${money(cash)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 16),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              style: const TextStyle(fontSize: 28, letterSpacing: 14, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(hintText: '• • • •'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
          onPressed: _code.text.length == 4 ? () => Navigator.pop(context, _code.text) : null,
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}
