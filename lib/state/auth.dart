import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../data/repository.dart';
import '../models/models.dart';

class AuthState {
  const AuthState({this.user});
  final User? user;
  bool get isLoggedIn => user != null;
}

class AuthController extends Notifier<AuthState> {
  static const _userKey = 'auth_user';

  @override
  AuthState build() {
    final tokens = ref.watch(tokenStoreProvider);
    // أي 401 من السيرفر = خروج تلقائي.
    tokens.onUnauthorized = () => _clearLocal();
    // السائق لم يعد معتمدًا → نحدّث الحساب فينقله الراوتر لشاشة انتظار الموافقة.
    tokens.onNotApproved = () {
      if (state.user?.driver?.isApproved ?? false) refresh().ignore();
    };

    final raw = ref.watch(prefsProvider).getString(_userKey);
    if (tokens.token == null || raw == null) return const AuthState();
    return AuthState(user: User.fromJson(jsonDecode(raw)));
  }

  Future<void> signIn(LoginResult result) async {
    await ref.read(tokenStoreProvider).save(result.token);
    // رد login لا يحتوي حالة اعتماد السائق ولا مستنداته (تظهر لصاحب التوكن فقط) → نحمّل /me.
    var user = result.user;
    try {
      user = await ref.read(repositoryProvider).me();
    } catch (_) {
      // شاشة الانتظار تعيد التحميل تلقائيًا.
    }
    await _saveUser(user);
  }

  /// يعيد تحميل الحساب من السيرفر (حالة الاعتماد، الكاش، المستندات...).
  Future<User?> refresh() async {
    if (state.user == null) return null;
    final user = await ref.read(repositoryProvider).me();
    await _saveUser(user);
    return user;
  }

  Future<void> signOut() async {
    try {
      await ref.read(repositoryProvider).logout();
    } catch (_) {
      // حتى لو فشل الطلب نخرج محليًا.
    }
    await _clearLocal();
  }

  Future<void> _saveUser(User user) async {
    await ref.read(prefsProvider).setString(_userKey, jsonEncode(user.toJson()));
    state = AuthState(user: user);
  }

  Future<void> _clearLocal() async {
    await ref.read(tokenStoreProvider).clear();
    await ref.read(prefsProvider).remove(_userKey);
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
