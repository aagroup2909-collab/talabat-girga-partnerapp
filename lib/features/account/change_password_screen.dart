import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../auth/auth_widgets.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  Map<String, String> _errors = {};
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final errors = <String, String>{};
    if (_current.text.isEmpty) errors['current_password'] = 'اكتب كلمة المرور الحالية.';
    if (_password.text.length < minPasswordLength) {
      errors['password'] = 'كلمة المرور $minPasswordLength حروف أو أرقام على الأقل.';
    } else if (_confirm.text != _password.text) {
      errors['confirm'] = 'كلمتا المرور غير متطابقتين.';
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).changePassword(current: _current.text, password: _password.text);
      if (!mounted) return;
      showMessage(context, 'تم تغيير كلمة المرور.');
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      final server = {
        for (final field in ['current_password', 'password'])
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
      appBar: AppBar(title: const Text('تغيير كلمة المرور')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const FieldLabel('كلمة المرور الحالية'),
            PasswordField(
              controller: _current,
              hint: 'كلمة المرور الحالية',
              errorText: _errors['current_password'],
              textInputAction: TextInputAction.next,
            ),
            const FieldLabel('كلمة المرور الجديدة'),
            PasswordField(
              controller: _password,
              isNew: true,
              hint: '$minPasswordLength حروف أو أرقام على الأقل',
              errorText: _errors['password'],
              textInputAction: TextInputAction.next,
            ),
            const FieldLabel('تأكيد كلمة المرور الجديدة'),
            PasswordField(
              controller: _confirm,
              isNew: true,
              hint: 'اكتبها مرة تانية',
              errorText: _errors['confirm'],
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const ButtonSpinner() : const Text('حفظ'),
            ),
            const SizedBox(height: 8),
            // بعد زر الحفظ حتى ينتقل "التالي" في الكيبورد بين الحقول الثلاثة مباشرة.
            TextButton(
              onPressed: () => showForgotPasswordDialog(context),
              child: const Text('نسيت كلمة المرور الحالية؟'),
            ),
          ],
        ),
      ),
    );
  }
}
