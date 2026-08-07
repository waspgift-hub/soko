import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import '../../constants/tanzania_districts.dart';
import '../../models/product_model.dart';
import '../../services/api_config.dart';
import '../../widgets/input_field.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/location_map_widget.dart';
import '../../widgets/soko_vibe_loading.dart';
import '../../widgets/ds/ds.dart';
import '../../utils/network_error.dart';

class CheckoutScreen extends StatefulWidget {
  final Product product;

  const CheckoutScreen({super.key, required this.product});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _regionCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _landmarksCtrl = TextEditingController();
  bool _processing = false;
  bool _detecting = false;
  double? _latitude;
  double? _longitude;
  String _deliveryType = 'local';
  String? _selectedRegion;
  String? _selectedDistrict;

  static const List<String> _regions = [
    'Arusha', 'Dar es Salaam', 'Dodoma', 'Geita', 'Iringa', 'Kagera',
    'Katavi', 'Kigoma', 'Kilimanjaro', 'Lindi', 'Manyara', 'Mara',
    'Mbeya', 'Mjini Magharibi', 'Morogoro', 'Mtwara', 'Mwanza',
    'Njombe', 'Pwani', 'Rukwa', 'Ruvuma', 'Shinyanga', 'Simiyu',
    'Singida', 'Songwe', 'Tabora', 'Tanga',
  ];

  @override
  void dispose() {
    _regionCtrl.dispose();
    _streetCtrl.dispose();
    _landmarksCtrl.dispose();
    super.dispose();
  }

  void _matchRegion(String raw) {
    if (raw.isEmpty) return;
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'\s*(mkoa|region)\s*$'), '').trim();
    for (final r in _regions) {
      if (r.toLowerCase() == normalized) {
        _selectedRegion = r;
        return;
      }
    }
    for (final r in _regions) {
      if (r.toLowerCase().contains(normalized) || normalized.contains(r.toLowerCase())) {
        _selectedRegion = r;
        return;
      }
    }
  }

  /// Matches a geocoded district name against the current region's council
  /// list; returns null when there is no match so the user picks from the list.
  String? _matchDistrict(String raw) {
    if (raw.isEmpty || _selectedRegion == null) return null;
    final list = kRegionDistricts[_selectedRegion] ?? const <String>[];
    final normalized = raw.toLowerCase().trim();
    for (final d in list) {
      if (d.toLowerCase() == normalized) return d;
    }
    for (final d in list) {
      if (d.toLowerCase().contains(normalized) || normalized.contains(d.toLowerCase())) return d;
    }
    return null;
  }

  Future<void> _detectLocation() async {
    setState(() => _detecting = true);
    try {
      // Location service must be on and permission granted BEFORE positioning,
      // otherwise geolocator throws PERMISSION_DENIED without any system dialog.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() => _detecting = false);
        _showError(context.tr('location_disabled'));
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _detecting = false);
        _showError(
          perm == LocationPermission.deniedForever
              ? context.tr('location_denied')
              : context.tr('location_permission_denied'),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _latitude = pos.latitude;
      _longitude = pos.longitude;
      await _reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _detecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('address_filled_confirm')), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _detecting = false);
      _showError(context.tr('imeshindwa').replaceAll('{0}', 'location'));
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&addressdetails=1',
      );
      final resp = await http.get(uri, headers: {'User-Agent': 'SokoVibe/1.0'});
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) return;
      if (!mounted) return;
      final state = (address['state'] as String?) ?? '';
      setState(() {
        _regionCtrl.text = state;
        _matchRegion(state);
        _selectedDistrict = _matchDistrict((address['city_district'] as String?)
            ?? (address['municipality'] as String?)
            ?? (address['county'] as String?)
            ?? (address['state_district'] as String?)
            ?? '');
        _streetCtrl.text = (address['road'] as String?) ?? _streetCtrl.text;
        _landmarksCtrl.text = (address['suburb'] as String?)
            ?? (address['neighbourhood'] as String?)
            ?? _landmarksCtrl.text;
      });
    } catch (_) {}
  }

  void _onPinChanged(double lat, double lng) {
    setState(() {
      _latitude = lat;
      _longitude = lng;
    });
    _reverseGeocode(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.product;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('checkout')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GlassContainer(
            blur: 20,
            opacity: isDark ? 0.12 : 0.08,
            borderRadius: 20,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 64, height: 64,
                    color: cs.surfaceContainerHighest,
                    child: p.images.isNotEmpty
                        ? CachedNetworkImage(imageUrl: p.images.first, fit: BoxFit.cover, width: 64, height: 64)
                        : Icon(Icons.image, size: 28, color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(context.formatPrice(p.price),
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          GlassContainer(
            blur: 16,
            opacity: isDark ? 0.08 : 0.05,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Unaweka agizo bila malipo. Muuzaji atakupa gharama ya usafirishaji, kisha utalipa.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(context.tr('delivery_type'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DeliveryTypeChip(
                  label: context.tr('delivery_within_region'),
                  icon: Icons.location_city,
                  selected: _deliveryType == 'local',
                  color: cs.primary,
                  onTap: () => setState(() => _deliveryType = 'local'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DeliveryTypeChip(
                  label: context.tr('delivery_outside_region'),
                  icon: Icons.local_shipping,
                  selected: _deliveryType == 'regional',
                  color: cs.tertiary,
                  onTap: () => setState(() => _deliveryType = 'regional'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(context.tr('shipping_address'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _detecting ? null : _detectLocation,
            icon: _detecting
                ? SokoVibeThreeDotLoader(size: 18, dotSize: 4.5, color: cs.primary)
                : const Icon(Icons.my_location, size: 18),
            label: Text(context.tr('get_location')),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
            ),
          ),
          const SizedBox(height: 12),
          GlassContainer(
            blur: 16,
            opacity: isDark ? 0.08 : 0.05,
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedRegion,
                  decoration: InputDecoration(
                    hintText: context.tr('select_region'),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: true,
                    fillColor: cs.surface.withValues(alpha: 0.5),
                    isDense: true,
                  ),
                  items: _regions
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedRegion = v;
                      _selectedDistrict = null;
                      if (v != null) _regionCtrl.text = v;
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDistrict,
                  decoration: InputDecoration(
                    hintText: context.tr('district_hint'),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: true,
                    fillColor: cs.surface.withValues(alpha: 0.5),
                    isDense: true,
                  ),
                  items: (_selectedRegion == null
                          ? const <String>[]
                          : (kRegionDistricts[_selectedRegion] ?? const <String>[]))
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedDistrict = v),
                ),
                const SizedBox(height: 10),
                AppInputField(
                  controller: _streetCtrl,
                  hint: context.tr('street_hint'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                AppInputField(
                  controller: _landmarksCtrl,
                  hint: context.tr('landmarks_hint'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (_latitude != null && _longitude != null) ...[
            const SizedBox(height: 16),
            Text(context.tr('view_map'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
            const SizedBox(height: 8),
            LocationMapWidget(
              targetLat: _latitude,
              targetLng: _longitude,
              height: 200,
              showDistance: true,
              interactive: true,
              draggablePin: true,
              onLocationChanged: _onPinChanged,
            ),
          ],
          const SizedBox(height: 24),

          DsButton(
            label: _processing ? context.tr('sending') : context.tr('flow_place_order'),
            icon: Icons.send_rounded,
            loading: _processing,
            onPressed: _submitOrder,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
  }

  Future<void> _submitOrder() async {
    final region = _selectedRegion ?? _regionCtrl.text.trim();
    final district = _selectedDistrict ?? '';
    final street = _streetCtrl.text.trim();
    if (region.isEmpty || district.isEmpty || street.isEmpty) {
      _showError(context.tr('fill_full_address_error'));
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _processing = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _showError(context.tr('ingia_akaunti_kwanza')); setState(() => _processing = false); return; }

    try {
      final p = widget.product;
      final token = await user.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'buyerId': user.uid,
          'buyerName': user.displayName ?? '',
          'buyerPhone': user.phoneNumber ?? '',
          'sellerId': p.sellerId,
          'sellerName': p.sellerName,
          'productId': p.id,
          'productName': p.name,
          'productImage': p.images.isNotEmpty ? p.images.first : '',
          'productPrice': p.price,
          'region': region,
          'district': district,
          'street': street,
          'landmarks': _landmarksCtrl.text.trim(),
          'latitude': _latitude,
          'longitude': _longitude,
          'deliveryType': _deliveryType,
        }),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || data['success'] != true) {
        _showError(data['error'] ?? 'Failed to create order');
        setState(() => _processing = false);
        return;
      }

      final orderData = data['order'] as Map<String, dynamic>;
      if (mounted) {
        setState(() => _processing = false);
        context.push('${AppRoutes.orderDetail}/${orderData['orderId']}', extra: orderData);
      }
    } catch (e) {
      final friendly = translateError(e);
      _showError(friendly);
      setState(() => _processing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }
}

class _DeliveryTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _DeliveryTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : cs.outline.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? color : cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? color : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
