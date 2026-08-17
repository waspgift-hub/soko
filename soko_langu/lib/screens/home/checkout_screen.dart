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
import '../../widgets/location_map_widget.dart';
import '../../widgets/soko_vibe_loading.dart';
import '../../utils/phone_utils.dart';
import '../../services/user_service.dart';

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
  final _phoneCtrl = TextEditingController();
  bool _processing = false;
  bool _detecting = false;
  double? _latitude;
  double? _longitude;
  String _deliveryType = 'local';
  String? _selectedRegion;
  String? _selectedDistrict;
  String? _selectedWard;

  @override
  void initState() {
    super.initState();
    _loadBuyerPhone();
  }

  Future<void> _loadBuyerPhone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final profile = await UserService().getProfile(user.uid);
    if (mounted && profile?.phone?.isNotEmpty == true) {
      _phoneCtrl.text = profile!.phone!;
    }
  }

  @override
  void dispose() {
    _regionCtrl.dispose();
    _streetCtrl.dispose();
    _landmarksCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _matchRegion(String raw) {
    if (raw.isEmpty) return;
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'\s*(mkoa|region)\s*$'), '').trim();
    for (final r in kRegions) {
      if (r.toLowerCase() == normalized) {
        _selectedRegion = r;
        return;
      }
    }
    for (final r in kRegions) {
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

  /// Matches a geocoded neighbourhood/suburb against the current district's
  /// kata list; returns null when there is no match so the user picks from the
  /// list (or leaves it empty, since the street is the required field).
  String? _matchWard(String raw) {
    if (raw.isEmpty || _selectedDistrict == null) return null;
    final list = kDistrictWards[_selectedDistrict] ?? const <String>[];
    final normalized = raw.toLowerCase().trim();
    for (final w in list) {
      if (w.toLowerCase() == normalized) return w;
    }
    for (final w in list) {
      if (w.toLowerCase().contains(normalized) || normalized.contains(w.toLowerCase())) return w;
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
      final suburb = (address['suburb'] as String?)
          ?? (address['neighbourhood'] as String?)
          ?? _landmarksCtrl.text;
      final district = _matchDistrict((address['city_district'] as String?)
          ?? (address['municipality'] as String?)
          ?? (address['county'] as String?)
          ?? (address['state_district'] as String?)
          ?? '');
      setState(() {
        _regionCtrl.text = state;
        _matchRegion(state);
        _selectedDistrict = district;
        _selectedWard = _matchWard(suburb);
        _streetCtrl.text = (address['road'] as String?) ?? _streetCtrl.text;
        _landmarksCtrl.text = suburb;
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
    final p = widget.product;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          context.tr('checkout'),
          style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _buildHeroProduct(context, cs, p),
                const SizedBox(height: 16),
                _buildTrustStrip(context, cs),
                const SizedBox(height: 20),

                _buildSectionTitle(context, cs, Icons.local_shipping_outlined, context.tr('delivery_type')),
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

                _buildSectionTitle(context, cs, Icons.home_outlined, context.tr('shipping_address')),
                const SizedBox(height: 12),
                _buildLocationButton(context, cs),
                const SizedBox(height: 12),
                _buildAddressForm(context, cs),
                const SizedBox(height: 20),
                _buildSectionTitle(context, cs, Icons.phone_outlined, context.tr('phone', 'Simu')),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    context.tr('checkout_phone_hint', 'Namba ya simu ya muuzaji kukuangalia'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '07XX XXX XXX',
                      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      prefixIcon: Icon(Icons.phone_android, color: cs.primary.withValues(alpha: 0.7)),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                if (_latitude != null && _longitude != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionTitle(context, cs, Icons.map_outlined, context.tr('view_map')),
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
              ],
            ),
          ),
          _buildBottomBar(context, cs),
        ],
      ),
    );
  }

  Widget _buildHeroProduct(BuildContext context, ColorScheme cs, Product p) {
    return Container(
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary.withValues(alpha: 0.18), cs.tertiary.withValues(alpha: 0.08)],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (p.images.isNotEmpty)
            Positioned(
              right: -20,
              top: -10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  width: 160,
                  height: 190,
                  child: CachedNetworkImage(
                    imageUrl: p.images.first,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(
                      color: cs.primary.withValues(alpha: 0.06),
                      child: Icon(Icons.image_rounded, size: 40, color: cs.primary.withValues(alpha: 0.2)),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    cs.surface.withValues(alpha: 0.85),
                    cs.surface.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 16,
            bottom: 16,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag_outlined, size: 13, color: cs.onPrimary),
                        const SizedBox(width: 5),
                        Text(
                          context.tr('checkout'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimary,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.formatPrice(p.price),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustStrip(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.secondary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: cs.secondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr('checkout_trust_strip', 'Unaweka agizo bila malipo. Muuzaji atakupa gharama ya usafirishaji, kisha utalipa.'),
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, ColorScheme cs, IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface),
        ),
      ],
    );
  }

  Widget _buildLocationButton(BuildContext context, ColorScheme cs) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _detecting ? null : _detectLocation,
        icon: _detecting
            ? SokoVibeThreeDotLoader(size: 18, dotSize: 4.5, color: cs.primary)
            : const Icon(Icons.my_location, size: 18),
        label: Text(context.tr('get_location')),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          backgroundColor: cs.primary.withValues(alpha: 0.06),
          side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildAddressForm(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.12)),
      ),
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
            items: kRegions
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
            onChanged: (v) {
              setState(() {
                _selectedDistrict = v;
                _selectedWard = null;
              });
            },
          ),
          if (_selectedDistrict != null &&
              (kDistrictWards[_selectedDistrict]?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedWard,
              decoration: InputDecoration(
                hintText: context.tr('ward_hint'),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: cs.surface.withValues(alpha: 0.5),
                isDense: true,
              ),
              items: kDistrictWards[_selectedDistrict]!
                  .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedWard = v),
            ),
          ],
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
    );
  }

  Widget _buildBottomBar(BuildContext context, ColorScheme cs) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  context.tr('flow_place_order'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                const Spacer(),
                Text(
                  context.formatPrice(widget.product.price),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _submitOrder,
                icon: _processing
                    ? SokoVibeThreeDotLoader(size: 20, dotSize: 5, color: cs.onPrimary)
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _processing ? context.tr('sending') : context.tr('flow_place_order'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
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
          'buyerPhone': _phoneCtrl.text.trim().isNotEmpty ? PhoneUtils.toE164(_phoneCtrl.text.trim()) : (user.phoneNumber ?? ''),
          'sellerId': p.sellerId,
          'sellerName': p.sellerName,
          'productId': p.id,
          'productName': p.name,
          'productImage': p.images.isNotEmpty ? p.images.first : '',
          'productPrice': p.price,
          'region': region,
          'district': district,
          'ward': _selectedWard ?? '',
          'street': street,
          'landmarks': _landmarksCtrl.text.trim(),
          'latitude': _latitude,
          'longitude': _longitude,
          'deliveryType': _deliveryType,
        }),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || data['success'] != true) {
        _showError(data['error'] ?? context.tr('failed_to_create_order', 'Failed to create order'));
        setState(() => _processing = false);
        return;
      }

      final orderData = data['order'] as Map<String, dynamic>;
      if (mounted) {
        setState(() => _processing = false);
        context.push('${AppRoutes.orderDetail}/${orderData['orderId']}', extra: orderData);
      }
    } catch (e) {
      final friendly = context.trError(e);
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
