// اختبار حي ضد السيرفر المحلي (بيانات DemoSeeder):
// flutter test test/api_smoke_test.dart --dart-define=API_BASE_URL=http://127.0.0.1:9123/api/v1 --dart-define=DEMO_PASSWORD=...
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talabat_girga_partner/core/api.dart';
import 'package:talabat_girga_partner/core/config.dart';
import 'package:talabat_girga_partner/data/repository.dart';
import 'package:talabat_girga_partner/models/models.dart';
import 'package:talabat_girga_partner/state/auth.dart';

const _password = String.fromEnvironment('DEMO_PASSWORD');

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)], retry: (_, _) => null);
  addTearDown(c.dispose);
  return c;
}

void main() {
  final local = AppConfig.apiBaseUrl.contains('127.0.0.1') && _password.isNotEmpty;

  test('driver login loads role and approval status', () async {
    final c = await _container();
    final repo = c.read(repositoryProvider);

    final result = await repo.login('01200000001', _password);
    expect(result.needsProfile, isFalse);
    await c.read(authProvider.notifier).signIn(result);

    final user = c.read(authProvider).user!;
    expect(user.isDriver, isTrue);
    expect(user.needsProfile, isFalse);
    expect(user.driver!.isApproved, isTrue);

    // نداءات السائق تُحلَّل بدون أخطاء.
    await repo.currentOrders();
    await repo.currentOffer();
    await repo.earnings();
    await repo.history();
  }, skip: !local);

  test('vendor login is routed by role', () async {
    final c = await _container();
    final result = await c.read(repositoryProvider).login('01111111111', _password);
    await c.read(authProvider.notifier).signIn(result);
    final user = c.read(authProvider).user!;
    expect(user.isVendor, isTrue);
    expect(user.needsProfile, isFalse);
  }, skip: !local);

  test('vendor endpoints parse', () async {
    final c = await _container();
    final repo = c.read(repositoryProvider);
    await c.read(authProvider.notifier).signIn(await repo.login('01111111111', _password));

    final store = await repo.vendorStore();
    expect(store.name, isNotEmpty);
    expect((await repo.vendorStores()).length, greaterThanOrEqualTo(1));

    for (final filter in ['new', 'active', 'history']) {
      await repo.vendorOrders(filter);
    }
    final history = await repo.vendorOrders('history');
    if (history.items.isNotEmpty) {
      final order = await repo.vendorOrder(history.items.first.id);
      expect(order.items, isNotEmpty);
    }

    await repo.categories();
    final products = await repo.products();
    expect(products.items, isNotEmpty);
    final p = products.items.first;
    // تبديل التوفر ثم إرجاعه كما كان.
    expect((await repo.setProductAvailable(p.id, !p.isAvailable)).isAvailable, !p.isAvailable);
    expect((await repo.setProductAvailable(p.id, p.isAvailable)).isAvailable, p.isAvailable);

    final now = DateTime.now();
    await repo.salesSummary(from: DateTime(now.year, now.month), to: now);
  }, skip: !local);

  test('vendor manages menu, hours and settlements', () async {
    final c = await _container();
    final repo = c.read(repositoryProvider);
    await c.read(authProvider.notifier).signIn(await repo.login('01111111111', _password));

    // قسم + منتج بإضافات ثم تعديل ثم حذف
    final category = await repo.saveCategory(name: 'اختبار ${DateTime.now().millisecondsSinceEpoch}');
    final created = await repo.saveProduct(
      name: 'منتج اختبار',
      description: 'وصف',
      price: 50,
      comparePrice: 60,
      categoryId: category.id,
      unit: ProductUnit.piece,
      isAvailable: true,
      isActive: false,
      options: [
        ProductOptionData(name: 'الحجم', isRequired: true, values: [OptionValueData(name: 'صغير'), OptionValueData(name: 'كبير', price: 15)]),
        ProductOptionData(name: 'إضافات', isMultiple: true, maxSelections: 2, values: [OptionValueData(name: 'جبنة', price: 10)]),
      ],
    );
    expect(created.categoryId, category.id);
    expect(created.isActive, isFalse);
    expect(created.editableOptions.length, 2);
    expect(created.editableOptions.first.values.last.price, 15);
    expect(created.editableOptions.last.isMultiple, isTrue);

    final updated = await repo.saveProduct(
      id: created.id,
      name: 'منتج اختبار 2',
      price: 55,
      unit: ProductUnit.kg,
      isAvailable: false,
      isActive: false,
      options: const [],
    );
    expect(updated.name, 'منتج اختبار 2');
    expect(updated.unit, ProductUnit.kg);
    expect(updated.categoryId, isNull);
    expect(updated.editableOptions, isEmpty);

    await repo.deleteProduct(created.id);
    await repo.setCategoryActive(category.id, false);
    await repo.deleteCategory(category.id);

    // مواعيد العمل: حفظ نفس المواعيد كما هي
    final hours = await repo.storeHours();
    expect(hours.length, 7);
    await repo.saveStoreHours(hours);

    // التسويات
    final finance = await repo.finance();
    expect(finance.methods, isNotEmpty);
    if (finance.payoutAvailable >= 1) {
      final r = await repo.createSettlementRequest(kind: SettlementKind.payoutRequest, amount: 1, method: 'cash');
      expect(r.isPending, isTrue);
      await repo.cancelSettlementRequest(r.id);
    }
    await repo.settlementRequests();
    await repo.statement();
  }, skip: !local);

  test('wrong password and customer number give the server message in errors.phone', () async {
    final c = await _container();
    final repo = c.read(repositoryProvider);

    for (final (phone, password) in [('01200000002', 'wrong-password'), ('01099999999', _password)]) {
      try {
        await repo.login(phone, password);
        fail('login should fail');
      } on ApiException catch (e) {
        expect(e.statusCode, 422);
        expect(e.fieldError('phone'), isNotEmpty);
      }
    }
  }, skip: !local);

  test('wrong current password is reported on current_password', () async {
    final c = await _container();
    final repo = c.read(repositoryProvider);
    await c.read(authProvider.notifier).signIn(await repo.login('01200000002', _password));

    try {
      await repo.changePassword(current: 'not-the-password', password: 'new-pass-1');
      fail('should fail');
    } on ApiException catch (e) {
      expect(e.fieldError('current_password'), isNotEmpty);
    }
  }, skip: !local);

  test('401 clears the session', () async {
    final c = await _container();
    final repo = c.read(repositoryProvider);
    await c.read(authProvider.notifier).signIn(await repo.login('01200000002', _password));
    expect(c.read(authProvider).isLoggedIn, isTrue);

    await c.read(tokenStoreProvider).save('invalid-token');
    await expectLater(repo.me(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(c.read(authProvider).isLoggedIn, isFalse);
    expect(c.read(tokenStoreProvider).token, isNull);
  }, skip: !local);
}
