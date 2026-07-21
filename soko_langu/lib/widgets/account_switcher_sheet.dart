import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/saved_account.dart';
import '../services/account_manager.dart';
import '../app/routes.dart';
import '../extensions/context_tr.dart';
import 'google_loading.dart';
import '../utils/network_error.dart';

class AccountSwitcherSheet extends StatefulWidget {
  const AccountSwitcherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AccountSwitcherSheet(),
    );
  }

  @override
  State<AccountSwitcherSheet> createState() => _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends State<AccountSwitcherSheet> {
  List<SavedAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await AccountManager.instance.getAccounts();
    if (mounted)
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
  }

  Future<void> _switchAccount(SavedAccount account) async {
    if (account.isActive) {
      Navigator.pop(context);
      return;
    }

    if (account.provider == 'google') {
      try {
        await AccountManager.instance.switchToAccountGoogle(account.uid);
        if (mounted) {
          Navigator.pop(context);
          context.go(AppRoutes.home);
        }
      } catch (e) {
        if (mounted) _showError('${context.tr('wrong_password_switch_error')}: ${translateError(e)}');
      }
    } else {
      if (!mounted) return;
      Navigator.pop(context);
      _showPasswordDialog(account);
    }
  }

  void _showPasswordDialog(SavedAccount account) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(account.email),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('enter_password_to_switch')),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.tr('password'),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await AccountManager.instance.switchToAccountEmail(
                  account.uid,
                  ctrl.text,
                );
                if (mounted) context.go(AppRoutes.home);
              } catch (e) {
                if (mounted) _showError(context.tr('wrong_password_switch_error'));
              }
            },
            child: Text(context.tr('switch_account')),
          ),
        ],
      ),
    );
  }

  Future<void> _addAccount() async {
    await AccountManager.instance.addAndSignOutForNewAccount();
    if (mounted) {
      Navigator.pop(context);
      context.go(AppRoutes.login);
    }
  }

  Future<void> _removeAccount(SavedAccount account) async {
    if (_accounts.length <= 1) {
      _showError(context.tr('cannot_remove_last_account'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('remove_account')),
        content: Text(context.tr('remove_account_confirm').replaceAll('{email}', account.email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('remove')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AccountManager.instance.removeAccount(account.uid);
      await _load();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  context.tr('accounts'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_accounts.length}',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: GoogleLoading(size: 24, strokeWidth: 2),
            ),
          if (!_loading)
            ..._accounts.map((account) => _buildAccountTile(account, cs)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addAccount,
                icon: const Icon(Icons.person_add_outlined, size: 20),
                label: Text(context.tr('add_another_account')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAccountTile(SavedAccount account, ColorScheme cs) {
    final isActive = account.isActive;
    final user = FirebaseAuth.instance.currentUser;
    final isCurrent = user?.uid == account.uid;

    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: cs.primaryContainer,
        backgroundImage: account.photoUrl != null
            ? NetworkImage(account.photoUrl!)
            : null,
        child: account.photoUrl == null
            ? Text(
                (account.displayName.isNotEmpty
                        ? account.displayName[0]
                        : account.email[0])
                    .toUpperCase(),
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(
        account.displayName,
        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
      ),
      subtitle: Row(
        children: [
          Text(
            account.email,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                context.tr('active'),
                style: TextStyle(
                  fontSize: 10,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isActive && !isCurrent)
            TextButton(
              onPressed: () => _switchAccount(account),
              child: Text(
                context.tr('switch_account'),
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
            onPressed: () => _removeAccount(account),
          ),
        ],
      ),
    );
  }
}
