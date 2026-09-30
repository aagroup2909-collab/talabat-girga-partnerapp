import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../state/auth.dart';
import 'auth_widgets.dart';

/// الدخول برقم الموبايل + كلمة المرور. الحسابات تنشئها الإدارة — لا يوجد تسجيل من التطبيق.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _phoneError;
  String? _passwordError;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final phone = normalizePhone(_phone.text);
    setState(() {
      _phoneError = isValidPhone(phone) ? null : 'اكتب رقم موبايل مصري صحيح (11 رقم).';
      _passwordError = _password.text.isEmpty ? 'اكتب كلمة المرور.' : null;
    });
    if (_phoneError != null || _passwordError != null) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(repositoryProvider).login(phone, _password.text);
      await ref.read(authProvider.notifier).signIn(result);
      // التوجيه يتم تلقائيًا من الراوتر حسب الدور وحالة الحساب.
    } on ApiException catch (e) {
      // 422: رسالة السيرفر في errors.phone — 429: "محاولات كثيرة" من ApiException.
      if (mounted) setState(() => _phoneError = e.fieldError('phone') ?? e.message);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supportPhone = (ref.watch(appConfigProvider).value?['support_phone'] as String?)?.trim() ?? '';

    return Scaffold(
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 36),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(26)),
                  child: const Icon(Icons.handshake_outlined, color: Colors.white, size: 50),
                ),
              ),
              const SizedBox(height: 20),
              const Text('طلبات جرجا — الشركاء', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('تطبيق السائقين والتجار', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 20),
              const FieldLabel('رقم الموبايل'),
              PhoneField(
                controller: _phone,
                errorText: _phoneError,
                onChanged: (_) {
                  if (_phoneError != null) setState(() => _phoneError = null);
                },
              ),
              const FieldLabel('كلمة المرور'),
              PasswordField(
                controller: _password,
                errorText: _passwordError,
                onChanged: (_) {
                  if (_passwordError != null || _phoneError != null) setState(() => _passwordError = _phoneError = null);
                },
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy ? const ButtonSpinner() : const Text('دخول'),
              ),
              const SizedBox(height: 20),
              const NoticeBox(
                icon: Icons.info_outline,
                text: 'الحساب بتعمله الإدارة. لو معندكش حساب أو نسيت كلمة المرور تواصل مع الإدارة',
              ),
              if (supportPhone.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => callPhone(supportPhone),
                  icon: const Icon(Icons.call_outlined),
                  label: Text('اتصل بالإدارة: $supportPhone'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
