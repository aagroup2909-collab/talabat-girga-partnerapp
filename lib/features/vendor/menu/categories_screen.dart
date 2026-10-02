import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/vendor.dart';

/// أقسام المنيو: إضافة، إعادة تسمية، إظهار/إخفاء، حذف.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Category? category]) async {
    final name = await showDialog<String>(context: context, builder: (_) => _NameDialog(initial: category?.name));
    if (name == null || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).saveCategory(id: category?.id, name: name);
      ref.invalidate(categoriesProvider);
      if (context.mounted) showMessage(context, category == null ? 'تمت إضافة القسم.' : 'تم الحفظ.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, Category c, bool active) async {
    try {
      await ref.read(repositoryProvider).setCategoryActive(c.id, active);
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف قسم "${c.name}"؟'),
        content: const Text('المنتجات اللي فيه مش هتتحذف، هتبقى بدون قسم.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deleteCategory(c.id);
      ref.invalidate(categoriesProvider);
      if (context.mounted) showMessage(context, 'تم حذف القسم.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('أقسام المنيو')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('قسم جديد'),
      ),
      body: switch (async) {
        AsyncValue(:final value?) when value.isEmpty => const EmptyView(
            icon: Icons.category_outlined,
            title: 'لا توجد أقسام',
            subtitle: 'قسّم المنيو (مشويات، سندوتشات، مشروبات...) عشان العميل يلاقي اللي عايزه بسرعة.',
          ),
        AsyncValue(:final value?) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = value[i];
              return Card(
                child: ListTile(
                  title: Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: c.isActive ? AppColors.ink : AppColors.muted)),
                  subtitle: c.isActive ? null : const Text('مخفي عن العملاء'),
                  onTap: () => _edit(context, ref, c),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: c.isActive, onChanged: (v) => _toggle(context, ref, c, v)),
                      IconButton(
                        onPressed: () => _delete(context, ref, c),
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        AsyncValue(:final error?) => ErrorView(error: error, onRetry: () => ref.invalidate(categoriesProvider)),
        _ => const LoadingView(),
      },
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({this.initial});

  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isNotEmpty) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'قسم جديد' : 'تعديل القسم'),
        content: TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'اسم القسم'),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(onPressed: _submit, child: const Text('حفظ')),
        ],
      );
}
