import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/repository.dart';

/// يقبل +20 / 0020 / أرقام عربية بمسافات ويرجع 01xxxxxxxxx.
String normalizePhone(String input) {
  var p = input.replaceAll(RegExp(r'\D'), '');
  if (p.startsWith('0020')) p = p.substring(2);
  if (p.startsWith('20') && p.length == 12) p = '0${p.substring(2)}';
  return p;
}

bool isValidPhone(String phone) => RegExp(r'^01[0125]\d{8}$').hasMatch(phone);

const minPasswordLength = 6;

/// رسالة خطأ عربية تحت حقل اتجاهه LTR (رقم/كود): بدونها تظهر النقطة في أول الجملة.
Widget? rtlFieldError(BuildContext context, String? text) {
  if (text == null) return null;
  return SizedBox(
    width: double.infinity,
    child: Text(
      text,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.start,
      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5),
    ),
  );
}

class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller, this.errorText, this.autofocus = false, this.enabled = true, this.onChanged, this.onSubmitted});

  final TextEditingController controller;
  final String? errorText;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    // الأرقام تُكتب من اليسار لليمين حتى في الواجهة العربية.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.telephoneNumber],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
        style: const TextStyle(fontSize: 18, letterSpacing: 1),
        decoration: InputDecoration(
          hintText: '01xxxxxxxxx',
          prefixIcon: const Icon(Icons.phone_iphone),
          error: rtlFieldError(context, errorText),
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.hint = 'كلمة المرور',
    this.errorText,
    this.isNew = false,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final String? errorText;

  /// كلمة مرور جديدة (تسجيل / تغيير) أم حالية (دخول) — لمدير كلمات المرور.
  final bool isNew;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      autofillHints: [widget.isNew ? AutofillHints.newPassword : AutofillHints.password],
      inputFormatters: [LengthLimitingTextInputFormatter(72)],
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.lock_outline),
        errorText: widget.errorText,
        errorMaxLines: 3,
        // خارج ترتيب التنقل: زر "التالي" في الكيبورد يروح للحقل التالي لا لأيقونة العين.
        suffixIcon: ExcludeFocus(
          child: IconButton(
            tooltip: _hidden ? 'إظهار' : 'إخفاء',
            onPressed: () => setState(() => _hidden = !_hidden),
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 16),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white));
}

/// مربع ملاحظة ملوّن (معلومة / تنبيه).
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, required this.icon, required this.text, this.color = AppColors.primary});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.5, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}

/// نسيان كلمة المرور: لا يوجد استرجاع ذاتي — الإدارة تعيّن كلمة جديدة.
Future<void> showForgotPasswordDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final config = ref.watch(appConfigProvider);
        final phone = (config.value?['support_phone'] as String?)?.trim() ?? '';

        return AlertDialog(
          title: const Text('نسيت كلمة المرور؟'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تواصل مع الإدارة وهتحدد لك كلمة مرور جديدة.', style: TextStyle(height: 1.5)),
              const SizedBox(height: 14),
              if (config.isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
              else if (phone.isNotEmpty)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(phone, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            if (phone.isNotEmpty)
              FilledButton.icon(
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                icon: const Icon(Icons.call),
                label: const Text('اتصال'),
              ),
          ],
        );
      },
    ),
  );
}
