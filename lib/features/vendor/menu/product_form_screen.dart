import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/vendor.dart';
import '../../auth/auth_widgets.dart';

/// إضافة منتج أو تعديله: البيانات، الصورة، القسم، والإضافات (أحجام / إضافات اختيارية).
/// يرجع true لما يتغير المنيو (حفظ أو حذف).
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product});

  final Product? product;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _description = TextEditingController(text: widget.product?.description ?? '');
  late final _price = TextEditingController(text: _num(widget.product?.price));
  late final _comparePrice = TextEditingController(text: _num(widget.product?.comparePrice));
  late int? _categoryId = widget.product?.categoryId;
  late ProductUnit _unit = widget.product?.unit ?? ProductUnit.piece;
  late bool _available = widget.product?.isAvailable ?? true;
  late bool _active = widget.product?.isActive ?? true;
  late final List<ProductOptionData> _options = widget.product?.editableOptions ?? [];
  String? _imagePath;
  Map<String, String> _errors = {};
  bool _busy = false;

  bool get _isEdit => widget.product != null;

  static String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _comparePrice.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 80);
    if (file != null) setState(() => _imagePath = file.path);
  }

  Map<String, String> _validate() {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = 'اكتب اسم المنتج.';
    final price = double.tryParse(_price.text);
    if (price == null || price < 0) e['price'] = 'اكتب السعر.';
    final compare = _comparePrice.text.isEmpty ? null : double.tryParse(_comparePrice.text);
    if (_comparePrice.text.isNotEmpty && (compare == null || (price != null && compare <= price))) {
      e['compare_price'] = 'السعر قبل الخصم لازم يكون أكبر من السعر.';
    }
    for (final (i, o) in _options.indexed) {
      if (o.name.trim().isEmpty) e['options.$i'] = 'اكتب اسم المجموعة (مثال: الحجم).';
      if (o.values.isEmpty || o.values.any((v) => v.name.trim().isEmpty)) e['options.$i'] = 'اكتب اسم كل اختيار أو احذفه.';
    }
    return e;
  }

  Future<void> _save() async {
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      showMessage(context, errors.values.first);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveProduct(
            id: widget.product?.id,
            name: _name.text.trim(),
            description: _description.text.trim(),
            price: double.parse(_price.text),
            comparePrice: _comparePrice.text.isEmpty ? null : double.parse(_comparePrice.text),
            categoryId: _categoryId,
            unit: _unit,
            isAvailable: _available,
            isActive: _active,
            options: _options,
            imagePath: _imagePath,
          );
      if (!mounted) return;
      showMessage(context, _isEdit ? 'تم حفظ التعديلات.' : 'تمت إضافة المنتج.');
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = {for (final entry in e.errors.entries) entry.key: entry.value.first});
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنتج؟'),
        content: Text('هيتشال "${widget.product!.name}" من المنيو نهائيًا. لو عايز تخفيه مؤقتًا خليه "غير متوفر" بدل الحذف.'),
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
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteProduct(widget.product!.id);
      if (!mounted) return;
      showMessage(context, 'تم حذف المنتج.');
      context.pop(true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل المنتج' : 'منتج جديد'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'حذف',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  _imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(File(_imagePath!), width: 120, height: 120, fit: BoxFit.cover),
                        )
                      : NetImage(widget.product?.image, width: 120, height: 120, radius: 16, icon: Icons.add_a_photo_outlined),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary,
                      child: const Icon(Icons.edit, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const FieldLabel('اسم المنتج'),
          TextField(controller: _name, decoration: InputDecoration(hintText: 'مثال: سندوتش شاورما', errorText: _errors['name'])),
          const FieldLabel('الوصف (اختياري)'),
          TextField(controller: _description, minLines: 2, maxLines: 4, decoration: InputDecoration(hintText: 'المكونات، الحجم...', errorText: _errors['description'])),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('السعر'),
                    _MoneyField(controller: _price, error: _errors['price']),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('قبل الخصم (اختياري)'),
                    _MoneyField(controller: _comparePrice, error: _errors['compare_price']),
                  ],
                ),
              ),
            ],
          ),
          const FieldLabel('القسم'),
          DropdownButtonFormField<int?>(
            initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
            items: [
              const DropdownMenuItem(value: null, child: Text('بدون قسم')),
              for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
            decoration: InputDecoration(errorText: _errors['category_id']),
          ),
          const FieldLabel('الوحدة'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in ProductUnit.values)
                ChoiceChip(label: Text(u.label), selected: _unit == u, onSelected: (_) => setState(() => _unit = u)),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                  title: const Text('متوفر الآن'),
                  subtitle: const Text('اقفله لو المنتج خلص مؤقتًا'),
                ),
                const Divider(),
                SwitchListTile(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('ظاهر في المنيو'),
                  subtitle: const Text('اقفله لإخفاء المنتج عن العملاء تمامًا'),
                ),
              ],
            ),
          ),
          SectionTitle(
            'الإضافات والأحجام',
            trailing: TextButton.icon(
              onPressed: () => setState(() => _options.add(ProductOptionData())),
              icon: const Icon(Icons.add),
              label: const Text('مجموعة'),
            ),
          ),
          if (_options.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('مثال: "الحجم" (صغير / وسط / كبير) أو "إضافات" (جبنة +10، صوص +5).',
                  style: TextStyle(color: AppColors.muted)),
            ),
          for (final (i, o) in _options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionEditor(
                key: ObjectKey(o),
                option: o,
                error: _errors['options.$i'],
                onChanged: () => setState(() => _errors.remove('options.$i')),
                onRemove: () => setState(() => _options.removeAt(i)),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const ButtonSpinner() : Text(_isEdit ? 'حفظ التعديلات' : 'إضافة المنتج'),
          ),
        ],
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, this.error});

  final TextEditingController controller;
  final String? error;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
        decoration: InputDecoration(suffixText: 'ج.م', errorText: error, errorMaxLines: 2),
      );
}

/// محرر مجموعة إضافات واحدة.
class _OptionEditor extends StatefulWidget {
  const _OptionEditor({super.key, required this.option, required this.onChanged, required this.onRemove, this.error});

  final ProductOptionData option;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final String? error;

  @override
  State<_OptionEditor> createState() => _OptionEditorState();
}

class _OptionEditorState extends State<_OptionEditor> {
  ProductOptionData get o => widget.option;

  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: widget.error != null ? AppColors.danger : AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: o.name,
                    decoration: const InputDecoration(hintText: 'اسم المجموعة (مثال: الحجم)'),
                    onChanged: (v) => _update(() => o.name = v),
                  ),
                ),
                IconButton(onPressed: widget.onRemove, icon: const Icon(Icons.delete_outline, color: AppColors.danger)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(label: const Text('اختيار واحد'), selected: !o.isMultiple, onSelected: (_) => _update(() => o.isMultiple = false)),
                ChoiceChip(label: const Text('أكثر من اختيار'), selected: o.isMultiple, onSelected: (_) => _update(() => o.isMultiple = true)),
                FilterChip(label: const Text('إجباري'), selected: o.isRequired, onSelected: (v) => _update(() => o.isRequired = v)),
              ],
            ),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(widget.error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ),
            const SizedBox(height: 8),
            for (final (j, v) in o.values.indexed)
              Padding(
                key: ObjectKey(v),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: v.name,
                        decoration: const InputDecoration(hintText: 'الاختيار (مثال: كبير)', isDense: true),
                        onChanged: (s) => _update(() => v.name = s),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: v.price == 0 ? '' : _ProductFormScreenState._num(v.price),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        decoration: const InputDecoration(hintText: 'سعر إضافي', suffixText: 'ج.م', isDense: true),
                        onChanged: (s) => _update(() => v.price = double.tryParse(s) ?? 0),
                      ),
                    ),
                    IconButton(
                      tooltip: v.isAvailable ? 'متوفر' : 'غير متوفر',
                      onPressed: () => _update(() => v.isAvailable = !v.isAvailable),
                      icon: Icon(v.isAvailable ? Icons.check_circle : Icons.remove_circle_outline,
                          color: v.isAvailable ? AppColors.success : AppColors.muted),
                    ),
                    IconButton(
                      onPressed: o.values.length > 1 ? () => _update(() => o.values.removeAt(j)) : null,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _update(() => o.values.add(OptionValueData())),
                icon: const Icon(Icons.add),
                label: const Text('اختيار'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
