import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/account/account_screen.dart';
import 'features/account/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/not_ready_screen.dart';
import 'features/driver/earnings/earnings_screen.dart';
import 'features/driver/history/history_screen.dart';
import 'features/driver/home/driver_home_screen.dart';
import 'features/driver/offer/offer_screen.dart';
import 'features/driver/info/approval_screen.dart';
import 'features/driver/info/driver_info_screen.dart';
import 'features/driver/order/active_order_screen.dart';
import 'features/support/support_screens.dart';
import 'features/vendor/finance/finance_screen.dart';
import 'features/vendor/menu/categories_screen.dart';
import 'features/vendor/menu/product_form_screen.dart';
import 'features/vendor/orders/vendor_order_screen.dart';
import 'features/vendor/orders/vendor_orders_screen.dart';
import 'features/vendor/products/products_screen.dart';
import 'features/vendor/sales/sales_screen.dart';
import 'features/vendor/store/hours_screen.dart';
import 'models/models.dart';
import 'state/auth.dart';
import 'state/driver.dart';
import 'state/vendor.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// أين يجب أن يكون المستخدم حسب دوره وحالة حسابه (null = في أي مكان مسموح).
String? _redirect(User? user, String path) {
  if (user == null) return path == '/login' ? null : '/login';

  // needs_profile: الإدارة لم تجهّز الحساب بعد (سائق بلا بيانات / تاجر بلا متجر) → شاشة حاجزة.
  if (user.needsProfile) return path == '/not-ready' ? null : '/not-ready';

  // مسارات مشتركة متاحة في كل الحالات بعد الدخول.
  if (path.startsWith('/support') || path == '/change-password') return null;

  if (user.isVendor) return path.startsWith('/vendor') ? null : '/vendor';

  // السائق غير المعتمد يرى شاشة انتظار الموافقة فقط (+ بياناتي).
  if (!user.driver!.isApproved) {
    return path == '/driver/pending' || path == '/driver/info' ? null : '/driver/pending';
  }
  if (path == '/login' || path == '/not-ready' || path == '/driver/pending' || path.startsWith('/vendor')) return '/';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  // الراوتر يعيد تقييم redirect عند تغيّر حالة الدخول.
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref.read(authProvider).user, state.matchedLocation),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/not-ready', builder: (_, _) => const NotReadyScreen()),

      // ---------- السائق ----------
      GoRoute(path: '/driver/pending', builder: (_, _) => const ApprovalScreen()),
      GoRoute(path: '/driver/info', builder: (_, _) => const DriverInfoScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _DriverShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const DriverHomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/earnings', builder: (_, _) => const EarningsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())]),
        ],
      ),
      GoRoute(
        path: '/order/:id',
        builder: (_, s) => ActiveOrderScreen(orderId: int.parse(s.pathParameters['id']!)),
      ),

      // ---------- التاجر ----------
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _VendorShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/vendor', builder: (_, _) => const VendorOrdersScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/vendor/products', builder: (_, _) => const ProductsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/vendor/sales', builder: (_, _) => const SalesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/vendor/account', builder: (_, _) => const AccountScreen())]),
        ],
      ),
      GoRoute(path: '/vendor/finance', builder: (_, _) => const FinanceScreen()),
      GoRoute(path: '/vendor/hours', builder: (_, _) => const HoursScreen()),
      GoRoute(path: '/vendor/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/vendor/product/new', builder: (_, _) => const ProductFormScreen()),
      GoRoute(path: '/vendor/product/edit', builder: (_, s) => ProductFormScreen(product: s.extra as Product?)),
      GoRoute(
        path: '/vendor/order/:id',
        builder: (_, s) => VendorOrderScreen(orderId: int.parse(s.pathParameters['id']!)),
      ),

      // ---------- مشترك ----------
      GoRoute(path: '/change-password', builder: (_, _) => const ChangePasswordScreen()),
      GoRoute(path: '/support', builder: (_, _) => const TicketsScreen()),
      GoRoute(path: '/support/:id', builder: (_, s) => TicketScreen(ticketId: int.parse(s.pathParameters['id']!))),
    ],
  );
});

/// الهيكل الرئيسي للسائق: يعرض العروض الجديدة فوق أي شاشة.
class _DriverShell extends ConsumerStatefulWidget {
  const _DriverShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<_DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<_DriverShell> with WidgetsBindingObserver {
  int? _shownOfferId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // تحديث الحساب عند الفتح (الكاش، الاعتماد...).
    Future.microtask(() => ref.read(authProvider.notifier).refresh().catchError((_) => null));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(currentOrdersProvider);
      final offer = ref.read(driverSessionProvider).offer;
      if (offer != null) _showOffer(offer);
    }
  }

  void _showOffer(Offer offer) {
    if (_shownOfferId == offer.id) return;
    _shownOfferId = offer.id;
    _rootKey.currentState?.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => OfferScreen(offer: offer),
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(driverSessionProvider.select((s) => s.offer), (_, offer) {
      if (offer != null) _showOffer(offer);
    });

    final shell = widget.shell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'الأرباح'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'السجل'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}

/// الهيكل الرئيسي للتاجر: يبقي مراقب الطلبات الجديدة شغالًا (رنين) في كل التبويبات.
class _VendorShell extends ConsumerStatefulWidget {
  const _VendorShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<_VendorShell> createState() => _VendorShellState();
}

class _VendorShellState extends ConsumerState<_VendorShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(newOrdersProvider.notifier).refresh();
      ref.invalidate(vendorActiveOrdersProvider);
      ref.invalidate(vendorStoreProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final newCount = ref.watch(newOrdersProvider.select((s) => s.orders.length));
    // طلب جديد وأنت في تبويب آخر → ارجع لتبويب الطلبات.
    ref.listen(newOrdersProvider.select((s) => s.orders.length), (prev, next) {
      if (next > (prev ?? 0) && widget.shell.currentIndex != 0) widget.shell.goBranch(0);
    });

    final shell = widget.shell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: newCount > 0, label: Text('$newCount'), child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: Badge(isLabelVisible: newCount > 0, label: Text('$newCount'), child: const Icon(Icons.receipt_long)),
            label: 'الطلبات',
          ),
          const NavigationDestination(icon: Icon(Icons.fastfood_outlined), selectedIcon: Icon(Icons.fastfood), label: 'المنتجات'),
          const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'المبيعات'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}

class PartnerApp extends ConsumerWidget {
  const PartnerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'طلبات جرجا - الشركاء',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
      // عربي أولًا: كل الواجهة من اليمين لليسار.
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
