import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/localization_service.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/secure_storage_service.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationsEnabled =
            prefs.getBool('push_notifications_enabled') ?? true;
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
              if (pinController.text.isEmpty ||
                  pinController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('pin_mismatch'))),
                );
                return;
              }
              await SecureStorageService.write(
                'app_lock_pin',
                pinController.text,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
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
                    setState(() => _notificationsEnabled = value);
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
              const Divider(),
              _buildTile(
                icon: Icons.pin,
                title: context.tr('set_pin'),
                onTap: _showPinSetupDialog,
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
                  color: themeManager.isDark
                      ? const Color(0xFF39FF14)
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  themeManager.isDark ? 'Dark Mode' : 'Light Mode',
                  style: TextStyle(
                    color: themeManager.isDark ? const Color(0xFF39FF14) : null,
                  ),
                ),
                subtitle: Text(context.tr('switch_theme')),
                value: themeManager.isDark,
                activeThumbColor: const Color(0xFF39FF14),
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
                    await AuthService().logout();
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
                    try {
                      await UserService().deleteMyAccount();
                      if (mounted)
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                    } catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$e')));
                    }
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
