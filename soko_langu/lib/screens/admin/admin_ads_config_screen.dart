import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ads/ad_config.dart';
import '../../services/ads/ad_frequency_controller.dart';
import '../../services/ads/ad_manager.dart';
import '../../services/ads/ad_remote_config.dart';
import '../../services/ads/ads_admin_api.dart';
import '../../theme/design_tokens.dart';

/// Admin controls for the centralized ad system.
///
/// Everything here writes to `app_settings/ad_config` through
/// `PUT /api/v1/admin/config/ads`. Because `AdRemoteConfigService` streams that
/// document, a change reaches connected devices within the config TTL without an
/// app release — including the emergency "ads off" switch.
class AdminAdsConfigScreen extends StatefulWidget {
  const AdminAdsConfigScreen({super.key});

  @override
  State<AdminAdsConfigScreen> createState() => _AdminAdsConfigScreenState();
}

class _AdminAdsConfigScreenState extends State<AdminAdsConfigScreen> {
  final AdsAdminApiClient _api = AdsAdminApiClient();

  AdRemoteConfig _draft = const AdRemoteConfig();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final remote = await _api.fetchConfig();
    // Fall back to the live streamed config so the screen is still usable when
    // the admin token cannot reach the API.
    final live = context.read<AdManager>().config;
    if (!mounted) return;
    setState(() {
      _draft = remote ?? live;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await _api.saveConfig(_draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved != null) _draft = saved;
    });
    if (saved == null) {
      _toast('Save failed');
      return;
    }
    // Optimistically apply locally so the admin's own device reflects the change
    // immediately; the Firestore stream reconciles it a moment later.
    context.read<AdManager>().remoteConfig.applyOptimistic(saved);
    context.read<AdManager>().frequency.updatePolicy(saved.policy);
    _toast('Saved (v${saved.version})');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _patch({
    bool? adsEnabled,
    bool? banner,
    bool? native,
    bool? interstitial,
    bool? rewarded,
    bool? blueTickExempt,
  }) {
    setState(() {
      _draft = _draft.copyWith(
        adsEnabled: adsEnabled,
        bannerEnabled: banner,
        nativeEnabled: native,
        interstitialEnabled: interstitial,
        rewardedEnabled: rewarded,
        adsExemptBlueTickEnabled: blueTickExempt,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ads & Blue Tick')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Ds.sp4, Ds.sp4, Ds.sp4, Ds.sp8),
        children: [
          _Section(title: 'Master switches'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ads enabled'),
            subtitle: const Text('Emergency kill switch for all AdMob inventory'),
            value: _draft.adsEnabled,
            onChanged: (v) => _patch(adsEnabled: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Banner'),
            value: _draft.bannerEnabled,
            onChanged: _draft.adsEnabled ? (v) => _patch(banner: v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Native'),
            value: _draft.nativeEnabled,
            onChanged: _draft.adsEnabled ? (v) => _patch(native: v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Interstitial'),
            value: _draft.interstitialEnabled,
            onChanged: _draft.adsEnabled ? (v) => _patch(interstitial: v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rewarded'),
            value: _draft.rewardedEnabled,
            onChanged: _draft.adsEnabled ? (v) => _patch(rewarded: v) : null,
          ),

          const SizedBox(height: Ds.sp6),
          _Section(title: 'Blue Tick ad exemption'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Exempt Blue Tick sellers from ads'),
            subtitle: const Text(
              'When on, a seller with KYC=APPROVED and BlueTick=ACTIVE sees no '
              'AdMob inventory. Turning this off restores ads for everyone.',
            ),
            value: _draft.adsExemptBlueTickEnabled,
            onChanged: (v) => _patch(blueTickExempt: v),
          ),

          const SizedBox(height: Ds.sp6),
          _Section(title: 'Visibility ranking'),
          _NumberRow(
            label: 'Verified seller search boost',
            value: _draft.searchVerifiedBoost,
            min: 0,
            max: _draft.maxSearchVerifiedBoost,
            step: 0.01,
            format: (v) => '${(v * 100).toStringAsFixed(0)}% of relevance band',
            onChanged: (v) => setState(() {
              _draft = _draft.copyWith(
                searchVerifiedBoost: v.clamp(0.0, _draft.maxSearchVerifiedBoost),
              );
            }),
          ),
          _NumberRow(
            label: 'Hard ceiling',
            value: _draft.maxSearchVerifiedBoost,
            min: 0,
            max: 1,
            step: 0.05,
            format: (v) => '${(v * 100).toStringAsFixed(0)}%',
            onChanged: (v) => setState(() {
              _draft = _draft.copyWith(
                maxSearchVerifiedBoost: v,
                searchVerifiedBoost: _draft.searchVerifiedBoost.clamp(0.0, v),
              );
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow boost to outrank relevance'),
            subtitle: const Text(
              'Off by default. When off, the boost can only reorder inside a '
              'narrow relevance band, so a verified but irrelevant result can '
              'never displace a clearly better match.',
            ),
            value: _draft.allowBoostToOutrankRelevance,
            onChanged: (v) => setState(() {
              _draft = _draft.copyWith(allowBoostToOutrankRelevance: v);
            }),
          ),

          const SizedBox(height: Ds.sp6),
          _Section(title: 'Frequency capping'),
          _IntRow(
            label: 'Max interstitials per session',
            value: _draft.policy.maxInterstitialsPerSession,
            min: 0,
            max: 20,
            onChanged: (v) => _setPolicy(_draft.policy.copyWith(maxInterstitialsPerSession: v)),
          ),
          _IntRow(
            label: 'Max ads per session (all formats)',
            value: _draft.policy.maxAdsPerSession,
            min: 0,
            max: 100,
            onChanged: (v) => _setPolicy(_draft.policy.copyWith(maxAdsPerSession: v)),
          ),
          _IntRow(
            label: 'Min interval between interstitials (seconds)',
            value: _draft.policy.minIntervalBetweenInterstitials.inSeconds,
            min: 0,
            max: 7200,
            onChanged: (v) => _setPolicy(
                _draft.policy.copyWith(minIntervalBetweenInterstitials: Duration(seconds: v))),
          ),
          _IntRow(
            label: 'Grace period after launch (seconds)',
            value: _draft.policy.minTimeAfterLaunch.inSeconds,
            min: 0,
            max: 3600,
            onChanged: (v) => _setPolicy(
                _draft.policy.copyWith(minTimeAfterLaunch: Duration(seconds: v))),
          ),
          _IntRow(
            label: 'Min gap after any ad (seconds)',
            value: _draft.policy.minTimeAfterAnyAd.inSeconds,
            min: 0,
            max: 3600,
            onChanged: (v) => _setPolicy(
                _draft.policy.copyWith(minTimeAfterAnyAd: Duration(seconds: v))),
          ),
          _IntRow(
            label: 'Daily interstitial ceiling',
            value: _draft.policy.dailyInterstitialCeiling,
            min: 0,
            max: 200,
            onChanged: (v) =>
                _setPolicy(_draft.policy.copyWith(dailyInterstitialCeiling: v)),
          ),

          const SizedBox(height: Ds.sp6),
          _Section(title: 'Placement toggles'),
          ...AdPlacement.values
              .where((p) => p.format == AdFormat.banner)
              .map((placement) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: !_draft.disabledPlacements.contains(placement.id),
                    title: Text('${placement.id}  ·  ${placement.screen.name}'),
                    onChanged: (v) => setState(() {
                      final set = _draft.disabledPlacements.toSet();
                      if (v ?? false) {
                        set.remove(placement.id);
                      } else {
                        set.add(placement.id);
                      }
                      _draft = _draft.copyWith(disabledPlacements: set);
                    }),
                  )),

          const SizedBox(height: Ds.sp6),
          _Section(title: 'Debug'),
          _ReadOnlyRow(
            label: 'Your ad eligibility',
            value: context.watch<AdManager>().suppressionReason?.name ?? 'ads enabled',
          ),
          _ReadOnlyRow(
            label: 'SDK ready',
            value: context.watch<AdManager>().isSdkReady ? 'yes' : 'no',
          ),
          _ReadOnlyRow(
            label: 'Config version',
            value: '${_draft.version}',
          ),

          if (_error != null) ...[
            const SizedBox(height: Ds.sp4),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],

          const SizedBox(height: Ds.sp6),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving' : 'Save & broadcast'),
          ),
        ],
      ),
    );
  }

  void _setPolicy(AdFrequencyPolicy policy) {
    setState(() => _draft = _draft.copyWith(policy: policy));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.sp2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _IntRow extends StatelessWidget {
  const _IntRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Ds.sp1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 56,
            child: Text('$value', textAlign: TextAlign.center),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Ds.sp1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: ((max - min) / step).round().clamp(1, 200),
                  label: format(value),
                  onChanged: onChanged,
                ),
              ),
              SizedBox(width: 88, child: Text(format(value), style: const TextStyle(fontSize: 12))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
