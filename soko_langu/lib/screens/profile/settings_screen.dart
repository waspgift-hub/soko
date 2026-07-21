import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/localization_service.dart';
import '../../services/sms_language_preference.dart';
import '../../notifiers/auth_notifier.dart';
import '../../services/notification_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/app_lock_service.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../main.dart' show themeManager, AppConfig;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _pinConfigured = false;
  String _smsLang = 'sw';

  @override
  void initState() {
    super.initState();
    _load();
    AppLockService.instance.addListener(_onLockStateChanged);
  }

  @override
  void dispose() {
    AppLockService.instance.removeListener(_onLockStateChanged);
    super.dispose();
  }

  void _onLockStateChanged() {
    if (mounted) setState(() => _pinConfigured = AppLockService.instance.pinConfigured);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final pinSet = await AppLockService.instance.isPinSet();
    if (mounted) {
      setState(() {
        _notificationsEnabled =
            prefs.getBool('push_notifications_enabled') ?? true;
        _pinConfigured = pinSet;
        _smsLang = prefs.getString('sms_language') ?? 'sw';
      });
    }
  }

  void _showPinSetupDialog() {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('set_pin')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('enter_pin'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('confirm_pin'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
            onPressed: () async {
              if (pinController.text.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('pin_too_short'))),
                );
                return;
              }
              if (pinController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('pin_mismatch'))),
                );
                return;
              }
              final hashedPin = sha256.convert(utf8.encode(pinController.text)).toString();
              await SecureStorageService.write(
                'app_lock_pin',
                hashedPin,
              );
              await AppLockService.instance.onPinSaved();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => _pinConfigured = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('pin_updated'))),
                );
              }
            },
            child: Text(
              context.tr('save'),
              style:  TextStyle(color: Theme.of(context).colorScheme.surface),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('enter_password')),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: context.tr('password'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(context.tr('confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemovePin() async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('remove_pin')),
        content: Text(context.tr('remove_pin_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.tr('delete'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    await AppLockService.instance.clearPin();
    setState(() => _pinConfigured = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('pin_removed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              _buildSectionTitle(context.tr('notifications')),
              _buildTile(
                icon: Icons.notifications,
                title: context.tr('push_notifications'),
                trailing: Switch(
                  value: _notificationsEnabled,
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                  onChanged: (value) async {
                    final notif = NotificationService();
                    await notif.setEnabled(value);
                    if (mounted) setState(() => _notificationsEnabled = value);
                  },
                ),
              ),
              const Divider(),
              _buildSectionTitle(
                '${context.tr('language')} & ${context.tr('currency')}',
              ),
              _buildTile(
                icon: Icons.language,
                title: context.tr('language'),
                subtitle:
                    LocalizationService.supportedLanguages[config.langCode] ??
                    'Swahili',
                onTap: () => _showLanguagePicker(context, config),
              ),
              _buildTile(
                icon: Icons.attach_money,
                title: context.tr('currency'),
                subtitle:
                    "${config.currencyCode} (${LocalizationService.supportedCurrencies[config.currencyCode]?['symbol'] ?? 'TSh'})",
                onTap: () => _showCurrencyPicker(context, config),
              ),
              _buildTile(
                icon: Icons.sms,
                title: context.tr('sms_language'),
                subtitle: LocalizationService.supportedLanguages[_smsLang] ?? 'Swahili',
                onTap: () => _showSmsLanguagePicker(context),
              ),
              const Divider(),
              _buildTile(
                icon: Icons.pin,
                title: context.tr('set_pin'),
                subtitle: _pinConfigured ? context.tr('pin_enabled') : null,
                onTap: _showPinSetupDialog,
              ),
              if (_pinConfigured)
                _buildTile(
                  icon: Icons.lock_open,
                  title: context.tr('remove_pin'),
                  onTap: _confirmRemovePin,
                ),
              const Divider(),
              _buildSectionTitle(context.tr('account')),
              _buildTile(
                icon: Icons.person,
                title: context.tr('edit_profile'),
                onTap: () => context.push(AppRoutes.editProfile),
              ),
              const Divider(),
              _buildSectionTitle(context.tr('appearance')),
              SwitchListTile(
                secondary: Icon(
                  themeManager.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  themeManager.isDark ? context.tr('dark_mode') : context.tr('light_mode'),
                ),
                subtitle: Text(context.tr('switch_theme')),
                value: themeManager.isDark,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (val) => themeManager.setDark(val),
              ),
              const Divider(),
              _buildSectionTitle(context.tr('support')),
              _buildTile(
                icon: Icons.help,
                title: context.tr('help'),
                onTap: () => context.push(AppRoutes.help),
              ),
              _buildTile(
                icon: Icons.route_outlined,
                title: context.tr('how_it_works'),
                onTap: () => context.push(AppRoutes.orderFlow),
              ),
              _buildTile(
                icon: Icons.info,
                title: context.tr('about'),
                subtitle: context.tr('version'),
                onTap: () => context.push(AppRoutes.about),
              ),
              _buildTile(
                icon: Icons.privacy_tip_outlined,
                title: context.tr('privacy_policy'),
                onTap: () => context.push(AppRoutes.privacyPolicy),
              ),
              _buildTile(
                icon: Icons.article_outlined,
                title: context.tr('terms_of_service'),
                onTap: () => context.push(AppRoutes.termsOfService),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.tr('confirm_logout')),
                        content: Text(context.tr('logout_confirm_message')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.tr('cancel')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              context.tr('logout'),
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true || !mounted) return;
                    await context.read<AuthNotifier>().logout();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.surface),
                  label: Text(
                    context.tr('logout'),
                    style:  TextStyle(color: Theme.of(context).colorScheme.surface),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.tr('delete_account')),
                        content: Text(context.tr('delete_account_confirm')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.tr('cancel')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              context.tr('delete'),
                              style:  TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;

                    // Reauthentication required for email/password accounts
                    final hasPassword = FirebaseAuth.instance.currentUser?.providerData
                        .any((p) => p.providerId == 'password') ?? false;
                    if (hasPassword) {
                      final password = await _promptPassword();
                      if (password == null || !mounted) return;
                      try {
                        await UserService().reauthenticateAndDelete(password);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.tr('delete_account_failed'))),
                          );
                        }
                        return;
                      }
                    } else {
                      try {
                        await UserService().deleteMyAccount();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.tr('delete_account_failed'))),
                          );
                        }
                        return;
                      }
                    }
                    if (mounted)
                      Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.surface),
                  label: Text(
                    context.tr('delete_account'),
                    style:  TextStyle(color: Theme.of(context).colorScheme.surface),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.85),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  context.tr('contact'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, AppConfig config) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.tr('select_language'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...LocalizationService.supportedLanguages.entries.map(
            (e) => ListTile(
              title: Text(e.value),
              trailing: config.langCode == e.key
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                LocalizationService().setLanguage(e.key);
                config.onSetLanguage(e.key);
                Navigator.pop(ctx);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      ),
    );
  }

  void _showCurrencyPicker(BuildContext context, AppConfig config) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('select_currency'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...LocalizationService.supportedCurrencies.entries.map(
              (e) => ListTile(
                title: Text("${e.value['name']} (${e.value['symbol']})"),
                trailing: config.currencyCode == e.key
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  LocalizationService().setCurrency(e.key);
                  config.onSetCurrency(e.key);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSmsLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('select_sms_language'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...LocalizationService.supportedLanguages.entries.map(
              (e) => ListTile(
                title: Text(e.value),
                trailing: _smsLang == e.key
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  SmsLanguagePreference().set(e.key);
                  setState(() => _smsLang = e.key);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(
        title,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            )
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
