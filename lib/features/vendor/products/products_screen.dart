import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/vendor.dart';

/// المنتجات: بحث + أقسام + زر متوفر/غير متوفر، والضغط على المنتج يفتح التعديل.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  final _items = <Product>[];
  final _saving = <int>{};
  int? _categoryId;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  Timer? _debounce;

  /// يمنع نتيجة طلب قديم من الكتابة فوق نتيجة أحدث (بحث سريع).
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _generation++;
      _page = 0;
      _hasMore = true;
      _loading = false;
    }
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(repositoryProvider).products(categoryId: _categoryId, search: _search.text.trim(), page: _page + 1);
      if (!mounted || gen != _generation) return;
      setState(() {
        if (_page == 0) _items.clear();
        _items.addAll(res.items);
        _page++;
        _hasMore = res.hasMore;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Product p, bool available) async {
    final i = _items.indexWhere((x) => x.id == p.id);
    if (i < 0) return;
    // تحديث فوري للواجهة، ونرجع للحالة السابقة لو فشل الطلب.
    setState(() {
      _items[i] = p.copyWith(isAvailable: available);
      _saving.add(p.id);
    });
    try {
      final saved = await ref.read(repositoryProvider).setProductAvailable(p.id, available);
      if (!mounted) return;
      final j = _items.indexWhere((x) => x.id == p.id);
      if (j >= 0) setState(() => _items[j] = saved);
      showMessage(context, available ? '${p.name}: متوفر' : '${p.name}: غير متوفر');
    } catch (e) {
      if (!mounted) return;
      final j = _items.indexWhere((x) => x.id == p.id);
      if (j >= 0) setState(() => _items[j] = p);
      showError(context, e);
    } finally {
      if (mounted) setState(() => _saving.remove(p.id));
    }
  }

  /// فتح شاشة الإضافة/التعديل، وإعادة تحميل القائمة لو اتغير حاجة.
  Future<void> _openEditor(Product? p) async {
    final changed = await context.push<bool>(p == null ? '/vendor/product/new' : '/vendor/product/edit', extra: p);
    if (changed == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final unavailable = _items.where((p) => !p.isAvailable).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتجات'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/vendor/categories'),
            icon: const Icon(Icons.category_outlined),
            label: const Text('الأقسام'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.add),
        label: const Text('منتج جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'ابحث عن منتج',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load(reset: true);
                        },
                      ),
              ),
              onChanged: (_) {
                setState(() {});
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
              },
            ),
          ),
          if (categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final c in [null, ...categories])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(c?.name ?? 'الكل'),
                        selected: _categoryId == c?.id,
                        onSelected: (_) {
                          setState(() => _categoryId = c?.id);
                          _load(reset: true);
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (unavailable > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Text(
                    '$unavailable غير متوفر حاليًا ولا يظهر للعملاء كمتاح',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    if (_items.isEmpty) {
      if (_error != null) return ErrorView(error: _error!, onRetry: () => _load(reset: true));
      if (_loading) return const LoadingView();
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          children: [
            const SizedBox(height: 60),
            EmptyView(
              icon: Icons.fastfood_outlined,
              title: _search.text.isEmpty ? 'لا توجد منتجات' : 'لا نتائج',
              subtitle: 'اضغط "منتج جديد" لإضافة أول منتج.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) _load();
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: _items.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            if (i == _items.length) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
            final p = _items[i];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openEditor(p),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Opacity(
                        opacity: p.isAvailable ? 1 : 0.45,
                        child: NetImage(p.image, width: 56, height: 56, icon: Icons.fastfood_outlined),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, color: p.isAvailable ? AppColors.ink : AppColors.muted),
                            ),
                            const SizedBox(height: 2),
                            if (!p.isActive)
                              const Text(
                                'مخفي من المنيو',
                                style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
                              )
                            else
                              Text(
                                p.isAvailable ? money(p.price) : 'غير متوفر',
                                style: TextStyle(
                                  color: p.isAvailable ? AppColors.muted : AppColors.danger,
                                  fontWeight: p.isAvailable ? FontWeight.w500 : FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _saving.contains(p.id)
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: Spinner(color: AppColors.primary),
                            )
                          : Switch(value: p.isAvailable, activeThumbColor: AppColors.success, onChanged: (v) => _toggle(p, v)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
