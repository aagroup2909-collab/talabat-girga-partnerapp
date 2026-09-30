import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    // الأخطاء تظهر للمستخدم مع زر "إعادة المحاولة" بدل إعادة تلقائية صامتة.
    retry: (_, _) => null,
    child: const PartnerApp(),
  ));
}
