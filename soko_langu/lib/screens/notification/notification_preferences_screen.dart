import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/glass.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/soko_vibe_loading.dart';
import '../../constants/tanzania_districts.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  Map<String, dynamic>? _preferences;
  bool _loading = true;
  bool _saving = false;
  bool _smsEnabled = false;
  bool _districtEnabled = true;
  List<String> _interestedDistricts = [];
  String? _districtPicker;

  static const _masterKey = 'general';
  static const _channelKeys = [
    'payments',
    'chat',
    'orders',
    'marketing',
  ];
  static const _channelLabels = [
    'notification_payments',
    'notification_chat',
    'notification_orders',
    'notification_marketing',
  ];
  static const _channelIcons = [
    Icons.account_balance_wallet_outlined,
    Icons.chat_outlined,
    Icons.shopping_bag_outlined,
    Icons.campaign_outlined,
  ];

  static const String _base = '${ApiConfig.baseUrl}/api/notification';

  List<String> get _allDistricts => kRegionDistricts.values
      .expand((d) => d)
      .toSet()
      .toList()
    ..sort();

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
        _smsEnabled = prefs['sms_enabled'] as bool? ?? true;
        _districtEnabled = prefs['district_new_products'] as bool? ?? true;
        _interestedDistricts = List<String>.from(
          (prefs['interested_districts'] as List? ?? const []).map((e) => e.toString()),
        );
        _loading = false;
      });
    } catch (e) {
      debugPrint('NotificationPreferences load error: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _save(Map<String, dynamic> next) async {
    setState(() {
      _preferences = next;
      _smsEnabled = next['sms_enabled'] as bool? ?? true;
      _districtEnabled = next['district_new_products'] as bool? ?? true;
      _interestedDistricts = List<String>.from(
        (next['interested_districts'] as List? ?? const []).map((e) => e.toString()),
      );
      _saving = true;
    });
    try {
      final headers = await _authHeaders();
      await http.post(
        Uri.parse('$_base/preferences/set'),
        headers: headers,
        body: jsonEncode({'preferences': next}),
      );
    } catch (e) {
      debugPrint('NotificationPreferences save error: $e');
      setState(() {
        _preferences = Map<String, dynamic>.from(next);
      });
    } finally {
      setState(() => _saving = false);
    }
  }

  /// Master toggle: off silences every channel, on re-enables all of them.
  void _toggleMaster(bool value) {
    final next = Map<String, dynamic>.from(_preferences!);
    next[_masterKey] = value;
    for (final key in _channelKeys) {
      next[key] = value;
    }
    _save(next);
  }

  void _toggleChannel(String key, bool value) {
    final next = Map<String, dynamic>.from(_preferences!);
    next[key] = value;
    _save(next);
  }

  void _toggleSms(bool value) {
    final next = Map<String, dynamic>.from(_preferences!);
    next['sms_enabled'] = value;
    _save(next);
  }

  void _toggleDistrict(bool value) {
    final next = Map<String, dynamic>.from(_preferences!);
    next['district_new_products'] = value;
    _save(next);
  }

  void _addDistrict(String district) {
    if (district.isEmpty || _interestedDistricts.contains(district)) return;
    final next = Map<String, dynamic>.from(_preferences!);
    next['interested_districts'] = [..._interestedDistricts, district];
    _save(next);
  }

  void _removeDistrict(String district) {
    final next = Map<String, dynamic>.from(_preferences!);
    next['interested_districts'] =
        _interestedDistricts.where((d) => d != district).toList();
    _save(next);
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

    final masterOn = _preferences![_masterKey] as bool? ?? true;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('notification_preferences')),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SokoVibeThreeDotLoader(size: 20, dotSize: 5),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader(context, 'push_notifications_title'),
          const SizedBox(height: 8),
          _buildMasterTile(cs, masterOn),
          const SizedBox(height: 16),
          _buildSectionHeader(context, 'notification_preferences'),
          const SizedBox(height: 8),
          for (var i = 0; i < _channelKeys.length; i++)
            _buildChannelTile(
              cs,
              _channelKeys[i],
              _channelLabels[i],
              _channelIcons[i],
              masterOn,
            ),
          const SizedBox(height: 24),
          _buildSectionHeader(context, 'sms_notifications'),
          const SizedBox(height: 8),
          GlassCard(
            onTap: () => _toggleSms(!_smsEnabled),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: SwitchListTile(
              title: Text(context.tr('sms_for_payments')),
              subtitle: Text(
                context.tr('sms_notifications'),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              value: _smsEnabled,
              onChanged: _toggleSms,
              secondary: Icon(Icons.sms_outlined, color: cs.primary),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(context, 'district_notifications'),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: SwitchListTile(
              title: Text(
                context.tr('district_notifications'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.tr('district_notifications_hint'),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              value: _districtEnabled,
              onChanged: _toggleDistrict,
              secondary: Icon(Icons.location_city_outlined, color: cs.primary),
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: _districtEnabled ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !_districtEnabled,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _districtPicker,
                  decoration: InputDecoration(
                    labelText: context.tr('select_districts'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _allDistricts
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _addDistrict(value);
                    setState(() => _districtPicker = null);
                  },
                ),
                const SizedBox(height: 12),
                if (_interestedDistricts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      context.tr('no_districts_selected'),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _interestedDistricts
                        .map(
                          (d) => InputChip(
                            label: Text(d),
                            onDeleted: () => _removeDistrict(d),
                            deleteIconColor: cs.onSurfaceVariant,
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String key) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        context.tr(key),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.primary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildMasterTile(ColorScheme cs, bool masterOn) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SwitchListTile(
        title: Text(
          context.tr('notification_general'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          context.tr('notification_master_hint'),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        value: masterOn,
        onChanged: _toggleMaster,
        secondary: Icon(Icons.notifications_active_outlined, color: cs.primary),
      ),
    );
  }

  Widget _buildChannelTile(
    ColorScheme cs,
    String key,
    String labelKey,
    IconData icon,
    bool masterOn,
  ) {
    final value = (_preferences![key] as bool? ?? true) && masterOn;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: SwitchListTile(
          title: Text(
            context.tr(labelKey),
            style: TextStyle(
              color: masterOn ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
          value: value,
          onChanged: masterOn ? (v) => _toggleChannel(key, v) : null,
          secondary: Icon(
            icon,
            color: value ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
