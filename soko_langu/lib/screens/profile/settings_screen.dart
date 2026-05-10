import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../services/auth_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/localization_service.dart';
import '../../main.dart';
import '../../extensions/context_tr.dart';
import 'edit_profile_screen.dart';
import 'about_app_screen.dart';
import 'premium_upgrade_screen.dart';
import 'wallpaper_screen.dart';
import 'help_center_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  int _autoLockMinutes = 0;
  bool _useBiometric = false;
  String _accountTier = 'free';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final bio = await SecureStorageService.read('use_biometric');
    final tier = await UserService().getCurrentTier();
    if (mounted) {
      setState(() {
        _notificationsEnabled =
            prefs.getBool('push_notifications_enabled') ?? true;
        _autoLockMinutes = prefs.getInt('auto_lock_minutes') ?? 0;
        _useBiometric = bio == 'true';
        _accountTier = tier;
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
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
              style: const TextStyle(color: Colors.white),
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
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: SingleChildScrollView(
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
                activeThumbColor: Colors.green,
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
            _buildSectionTitle(context.tr('auto_lock')),
            _buildTile(
              icon: Icons.lock,
              title: context.tr('auto_lock_desc'),
              trailing: DropdownButton<int>(
                value: _autoLockMinutes,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: 0, child: Text(context.tr('never'))),
                  DropdownMenuItem(
                    value: 1,
                    child: Text('1 ${context.tr('minutes')}'),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text('2 ${context.tr('minutes')}'),
                  ),
                  DropdownMenuItem(
                    value: 5,
                    child: Text('5 ${context.tr('minutes')}'),
                  ),
                  DropdownMenuItem(
                    value: 10,
                    child: Text('10 ${context.tr('minutes')}'),
                  ),
                  DropdownMenuItem(
                    value: 30,
                    child: Text('30 ${context.tr('minutes')}'),
                  ),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  await autoLockService.setTimeout(value);
                  setState(() => _autoLockMinutes = value);
                },
              ),
            ),
            _buildTile(
              icon: Icons.pin,
              title: context.tr('set_pin'),
              onTap: _showPinSetupDialog,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint, color: Colors.green),
              title: Text(context.tr('use_biometric')),
              subtitle: Text(context.tr('use_biometric_sub')),
              value: _useBiometric,
              onChanged: (v) async {
                if (v) {
                  final localAuth = LocalAuthentication();
                  try {
                    final authed = await localAuth.authenticate(
                      localizedReason: context.tr('enroll_biometric'),
                      biometricOnly: true,
                    );
                    if (!authed) return;
                  } catch (_) {
                    return;
                  }
                }
                await SecureStorageService.write('use_biometric', v.toString());
                setState(() => _useBiometric = v);
              },
            ),
            const Divider(),
            _buildSectionTitle(context.tr('account')),
            _buildTile(
              icon: Icons.person,
              title: context.tr('edit_profile'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
            ),
            const Divider(),
            _buildSectionTitle(context.tr('account_tier')),
            _buildTile(
              icon: _accountTier == 'silver'
                  ? Icons.workspace_premium
                  : _accountTier == 'premium'
                  ? Icons.verified
                  : Icons.star,
              title: _accountTier == 'silver'
                  ? 'Silver ${context.tr('premium_active')}'
                  : _accountTier == 'premium'
                  ? context.tr('premium_active')
                  : context.tr('go_premium'),
              subtitle: _accountTier == 'silver'
                  ? context.tr('silver_feature_visibility')
                  : _accountTier == 'premium'
                  ? context.tr('premium_no_ads')
                  : context.tr('premium_subtitle'),
              trailing: _accountTier != 'free'
                  ? Icon(
                      Icons.check_circle,
                      color: _accountTier == 'silver'
                          ? Colors.blueGrey
                          : Colors.green,
                    )
                  : null,
              onTap: _accountTier != 'free'
                  ? null
                  : () => _showPremiumUpgrade(context),
            ),
            if (_accountTier == 'silver') ...[
              const Divider(),
              _buildSectionTitle(context.tr('appearance')),
              _buildTile(
                icon: Icons.wallpaper,
                title: context.tr('wallpaper'),
                subtitle: context.tr('wallpaper_sub'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WallpaperScreen()),
                  );
                },
              ),
            ],
            const Divider(),
            _buildSectionTitle(context.tr('support')),
            _buildTile(
              icon: Icons.help,
              title: context.tr('help'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
                );
              },
            ),
            _buildTile(
              icon: Icons.info,
              title: context.tr('about'),
              subtitle: context.tr('version'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutAppScreen()),
                );
              },
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
                icon: const Icon(Icons.logout, color: Colors.white),
                label: Text(
                  context.tr('logout'),
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
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
    );
  }

  void _showPremiumUpgrade(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PremiumUpgradeScreen()),
    ).then((_) async {
      final tier = await UserService().getCurrentTier();
      if (mounted) {
        setState(() => _accountTier = tier);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('account_tier', tier);
      }
    });
  }

  void _showLanguagePicker(BuildContext context, AppConfig config) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
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
                  ? const Icon(Icons.check, color: Colors.green)
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
    );
  }

  void _showCurrencyPicker(BuildContext context, AppConfig config) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.tr('select_currency'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...LocalizationService.supportedCurrencies.entries.map(
            (e) => ListTile(
              title: Text("${e.value['name']} (${e.value['symbol']})"),
              trailing: config.currencyCode == e.key
                  ? const Icon(Icons.check, color: Colors.green)
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
      leading: Icon(icon, color: Colors.green),
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
