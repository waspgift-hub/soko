import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  Map<String, dynamic>? _preferences;
  bool _loading = true;
  bool _saving = false;
  bool _smsEnabled = false;

  static const _channelKeys = ['general', 'payments', 'chat', 'orders', 'rides', 'marketing'];
  static const _channelLabels = [
    'notification_general',
    'notification_payments',
    'notification_chat',
    'notification_orders',
    'notification_rides',
    'notification_marketing',
  ];
  static const _channelIcons = [
    Icons.notifications_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.chat_outlined,
    Icons.shopping_bag_outlined,
    Icons.directions_car_outlined,
    Icons.campaign_outlined,
  ];

  static const String _base = '${ApiConfig.baseUrl}/api/notification';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$_base/preferences/get'),
        headers: headers,
        body: jsonEncode({}),
      );
      if (response.statusCode >= 400) throw Exception('Failed to load preferences');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final prefs = Map<String, dynamic>.from(data['preferences']);
      setState(() {
        _preferences = prefs;
        _smsEnabled = prefs['sms_enabled'] as bool? ?? false;
        _loading = false;
      });
    } catch (e) {
      debugPrint('NotificationPreferences load error: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() {
      _preferences![key] = value;
      _saving = true;
    });
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$_base/preferences/set'),
        headers: headers,
        body: jsonEncode({'preferences': _preferences}),
      );
    } catch (e) {
      debugPrint('NotificationPreferences save error: $e');
      setState(() => _preferences![key] = !value);
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: Text(context.tr('notification_preferences'))),
        body: const GoogleLoadingPage(),
      );
    }

    if (_preferences == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: Text(context.tr('notification_preferences'))),
        body: Center(child: Text(context.tr('no_notification_prefs'))),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('notification_preferences')),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.3)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                context.tr('push_notifications_title'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
              ),
            ),
            for (var i = 0; i < _channelKeys.length; i++)
              _buildChannelTile(cs, _channelKeys[i], _channelLabels[i], _channelIcons[i]),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                context.tr('sms_notifications'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('sms_for_payments')),
              subtitle: Text(context.tr('sms_notifications'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              value: _smsEnabled,
              onChanged: (v) => _toggle('sms_enabled', v),
              secondary: Icon(Icons.sms_outlined, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelTile(ColorScheme cs, String key, String labelKey, IconData icon) {
    final value = _preferences![key] as bool? ?? true;
    return SwitchListTile(
      title: Text(context.tr(labelKey)),
      value: value,
      onChanged: (v) => _toggle(key, v),
      secondary: Icon(icon, color: value ? cs.primary : cs.onSurfaceVariant),
    );
  }
}
