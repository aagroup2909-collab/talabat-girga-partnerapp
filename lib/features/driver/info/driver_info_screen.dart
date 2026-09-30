import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/widgets.dart';
import '../../../data/repository.dart';
import '../../../models/models.dart';
import '../../../state/auth.dart';
import '../../auth/auth_widgets.dart';
import 'documents_section.dart';

/// "بياناتي": بيانات المركبة والمستندات — اختيارية، فالإدارة هي التي تنشئ الحساب.
class DriverInfoScreen extends ConsumerStatefulWidget {
  const DriverInfoScreen({super.key});

  @override
  ConsumerState<DriverInfoScreen> createState() => _DriverInfoScreenState();
}

class _DriverInfoScreenState extends ConsumerState<DriverInfoScreen> {
  late final TextEditingController _name;
  late final TextEditingController _plate;
  late final TextEditingController _nationalId;
  VehicleType? _vehicle;
  Map<String, String> _errors = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    final driver = user?.driver;
    _name = TextEditingController(text: user?.name ?? '');
    _plate = TextEditingController(text: driver?.vehiclePlate ?? '');
    _nationalId = TextEditingController(text: driver?.nationalId ?? '');
    _vehicle = driver?.vehicleType ?? VehicleType.motorcycle;
    // login يرجع السائق بدون مستنداته — نحمّلها.
    Future.microtask(() => ref.read(authProvider.notifier).refresh().then((_) {}, onError: (_) {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _nationalId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final errors = <String, String>{};
    if (_name.text.trim().length < 3) errors['name'] = 'اكتب اسمك بالكامل.';
    if (_nationalId.text.length != 14) errors['national_id'] = 'الرقم القومي 14 رقم.';
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveDriverProfile(
            name: _name.text.trim(),
            vehicleType: _vehicle!,
            plate: _plate.text.trim(),
            nationalId: _nationalId.text.trim(),
          );
      await ref.read(authProvider.notifier).refresh();
      if (mounted) showMessage(context, 'تم حفظ البيانات.');
    } on ApiException catch (e) {
      if (!mounted) return;
      final server = {
        for (final field in ['name', 'vehicle_type', 'vehicle_plate', 'national_id'])
          if (e.fieldError(field) != null) field: e.fieldError(field)!,
      };
      if (server.isEmpty) {
        showError(context, e);
      } else {
        setState(() => _errors = server);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بياناتي')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionTitle('بيانات المركبة'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('الاسم بالكامل'),
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(hintText: 'الاسم كما في البطاقة', errorText: _errors['name']),
                  ),
                  const FieldLabel('نوع المركبة'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in VehicleType.values)
                        ChoiceChip(
                          label: Text(v.label),
                          selected: _vehicle == v,
                          onSelected: (_) => setState(() => _vehicle = v),
                        ),
                    ],
                  ),
                  const FieldLabel('رقم اللوحة (اختياري)'),
                  TextField(
                    controller: _plate,
                    decoration: InputDecoration(hintText: 'مثال: س ط ع 1234', errorText: _errors['vehicle_plate']),
                  ),
                  const FieldLabel('الرقم القومي'),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _nationalId,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
                      decoration: InputDecoration(hintText: '14 رقم', error: rtlFieldError(context, _errors['national_id'])),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy ? const ButtonSpinner() : const Text('حفظ'),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('المستندات'),
          const DocumentsSection(),
        ],
      ),
    );
  }
}
