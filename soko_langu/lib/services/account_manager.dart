import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_account.dart';

class AccountManager {
  static const _accountsKey = 'saved_accounts';

  AccountManager._();
  static final AccountManager instance = AccountManager._();

  bool _isSwitching = false;
  bool get isSwitching => _isSwitching;

  Future<List<SavedAccount>> getAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SavedAccount.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveAccounts(List<SavedAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(accounts.map((a) => a.toMap()).toList());
    await prefs.setString(_accountsKey, raw);
  }

  Future<SavedAccount?> getActiveAccount() async {
    final accounts = await getAccounts();
    try {
      return accounts.firstWhere((a) => a.isActive);
    } catch (_) {
      return null;
    }
  }

  Future<void> addOrUpdateAccount(SavedAccount account) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.uid == account.uid);
    accounts.insert(0, account.copyWith(isActive: true));
    final deactivated = accounts
        .sublist(1)
        .map((a) => a.copyWith(isActive: false))
        .toList();
    await _saveAccounts([account.copyWith(isActive: true), ...deactivated]);
  }

  Future<void> removeAccount(String uid) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.uid == uid);
    await _saveAccounts(accounts);
  }

  Future<void> switchToAccountEmail(String uid, String password) async {
    final accounts = await getAccounts();
    final idx = accounts.indexWhere((a) => a.uid == uid);
    if (idx == -1) return;
    final target = accounts[idx];

    _isSwitching = true;
    try {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: target.email,
        password: password,
      );

      final updated = accounts.asMap().entries.map((e) {
        return e.value.copyWith(isActive: e.key == idx);
      }).toList();
      await _saveAccounts(updated);
    } catch (e) {
      _isSwitching = false;
      rethrow;
    }
    _isSwitching = false;
  }

  Future<void> switchToAccountGoogle(String uid) async {
    final accounts = await getAccounts();
    final idx = accounts.indexWhere((a) => a.uid == uid);
    if (idx == -1) return;

    _isSwitching = true;
    try {
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance.authenticate();
      final GoogleSignInAuthentication auth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(idToken: auth.idToken);

      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInWithCredential(credential);

      final updated = accounts.asMap().entries.map((e) {
        return e.value.copyWith(isActive: e.key == idx);
      }).toList();
      await _saveAccounts(updated);
    } catch (e) {
      _isSwitching = false;
      rethrow;
    }
    _isSwitching = false;
  }

  Future<void> addAndSignOutForNewAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final existing = await getAccounts();
      if (!existing.any((a) => a.uid == user.uid)) {
        final account = SavedAccount(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? 'User',
          photoUrl: user.photoURL,
          provider: 'email',
          addedAt: DateTime.now(),
          isActive: false,
        );
        existing.add(account);
        await _saveAccounts(existing);
      }
    }
    await FirebaseAuth.instance.signOut();
  }

  Future<int> accountCount() async {
    final accounts = await getAccounts();
    return accounts.length;
  }
}
