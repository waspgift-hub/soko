import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../providers/ride_provider.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../models/ride_models.dart';
import '../../services/ride_api_service.dart';

class RideHomeScreen extends StatefulWidget {
  const RideHomeScreen({super.key});

  @override
  State<RideHomeScreen> createState() => _RideHomeScreenState();
}

class _RideHomeScreenState extends State<RideHomeScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Marker> _driverMarkers = {};
  LatLng? _currentLocation;
  MapType _mapType = MapType.normal;
  late AnimationController _bottomSheetCtrl;
  late Animation<Offset> _bottomSheetAnim;
  late AnimationController _pulseCtrl;

  final RideApiService _apiService = RideApiService();
  Timer? _nearbyDriversTimer;
  bool _searching = false;

  final List<RideOption> _rideOptions = [
    RideOption(icon: Icons.directions_car_rounded, name: 'Boda Bod', nameSw: 'Boda Bod', price: 'TSh 3,500', time: '2 min', color: 0xFF2196F3),
    RideOption(icon: Icons.airport_shuttle_rounded, name: 'Bajaji', nameSw: 'Bajaji', price: 'TSh 5,000', time: '3 min', color: 0xFF4CAF50),
    RideOption(icon: Icons.directions_car_filled_rounded, name: 'Car', nameSw: 'Gari', price: 'TSh 8,000', time: '5 min', color: 0xFFFF9800),
    RideOption(icon: Icons.local_shipping_rounded, name: 'Delivery', nameSw: 'Usafirishaji', price: 'TSh 6,500', time: '4 min', color: 0xFF9C27B0),
  ];

  @override
  void initState() {
    super.initState();
    _bottomSheetCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    );
    _bottomSheetAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _bottomSheetCtrl, curve: Curves.easeOutCubic),
    );
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomSheetCtrl.forward();
      context.read<RideProvider>().clearCurrentRide();
      context.read<RideProvider>().checkDriverStatus();
      _detectLocation();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _bottomSheetCtrl.dispose();
    _pulseCtrl.dispose();
    _nearbyDriversTimer?.cancel();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
        );
        _fetchNearbyDrivers(pos.latitude, pos.longitude);
      }
    } catch (_) {}
  }

  Future<void> _fetchNearbyDrivers(double lat, double lng) async {
    try {
      final drivers = await _apiService.getNearbyDrivers(lat: lat, lng: lng);
      if (!mounted) return;
      _driverMarkers.clear();
      for (final d in drivers) {
        _driverMarkers.add(Marker(
          markerId: MarkerId('driver_${d.driverId}'),
          position: LatLng(d.lat, d.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: d.name, snippet: '${d.distanceKm.toStringAsFixed(1)} km away'),
        ));
      }
      setState(() {});
    } catch (_) {}
    _nearbyDriversTimer = Timer(const Duration(seconds: 15), () {
      if (_currentLocation != null) {
        _fetchNearbyDrivers(_currentLocation!.latitude, _currentLocation!.longitude);
      }
    });
  }

  void _onMapCreated(GoogleMapController ctl) {
    _mapController = ctl;
    if (_currentLocation != null) {
      ctl.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation!, 15));
    }
  }

  void _openBooking() => context.push(AppRoutes.rideBooking);
  void _openRideHistory() => context.push(AppRoutes.rideHistory);

  void _showDestinationSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DestinationSearchSheet(
        apiService: _apiService,
        onSelect: (lat, lng, address) {
          Navigator.pop(ctx);
          context.push(AppRoutes.rideBooking, extra: {
            'destLat': lat,
            'destLng': lng,
            'destAddress': address,
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<RideProvider>();

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: _mapType,
            initialCameraPosition: CameraPosition(
              target: _currentLocation ?? const LatLng(-6.7924, 39.2083), zoom: 15,
            ),
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            markers: {..._markers, ..._driverMarkers},
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.45),
          ),
          // Gradient overlay at top for readability
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).padding.top + 100,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                ),
              ),
            ),
          ),
          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16, right: 16,
            child: SafeArea(
              bottom: false,
              child: Material(
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: IconButton(
                              icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                              onPressed: () => context.pop(),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: GestureDetector(
                              onTap: _showDestinationSearch,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(context.tr('where_to'),
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
                                        Text(context.tr('tap_map_dest'),
                                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: IconButton(
                              icon: Icon(Icons.history_rounded, color: cs.onSurfaceVariant, size: 20),
                              onPressed: _openRideHistory,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Right side map controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 100,
            right: 16,
            child: Column(
              children: [
                _mapButton(cs, Icons.my_location_rounded, () {
                  _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
                    _currentLocation ?? const LatLng(-6.7924, 39.2083), 15,
                  ));
                }),
                const SizedBox(height: 10),
                _mapButton(cs, _mapType == MapType.normal ? Icons.satellite_alt_rounded : Icons.map_rounded, _toggleMapType),
              ],
            ),
          ),
          // Bottom sheet
          SlideTransition(
            position: _bottomSheetAnim,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomSheet(context, cs, provider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapButton(ColorScheme cs, IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, size: 22, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  void _toggleMapType() => setState(() {
    _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal;
  });

  Widget _buildBottomSheet(BuildContext context, ColorScheme cs, RideProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 48, height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Icon(Icons.directions_car_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('where_to'),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: cs.onSurface)),
                        const SizedBox(height: 2),
                        Text(context.tr('tap_map_dest'),
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _showDestinationSearch,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(context.tr('search_button'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Ride options
              Row(
                children: _rideOptions.map((option) => Expanded(
                  child: _buildRideOptionCard(cs, option),
                )).toList(),
              ),
              const SizedBox(height: 16),
              // Quick actions
              Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      cs,
                      Icons.home_work_rounded,
                      context.tr('save_place'),
                      Colors.blue,
                      _showDestinationSearch,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildActionCard(
                      cs,
                      Icons.schedule_rounded,
                      context.tr('schedule'),
                      Colors.orange,
                      _showDestinationSearch,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildActionCard(
                      cs,
                      Icons.favorite_rounded,
                      context.tr('favorites'),
                      Colors.red,
                      _showDestinationSearch,
                    ),
                  ),
                ],
              ),
              // Driver section
              if (provider.isDriver) ...[
                const SizedBox(height: 16),
                _buildDriverSection(context, cs, provider),
              ],
              // Nearby drivers count
              if (_driverMarkers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.person_pin_circle, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Text('${_driverMarkers.length} ${context.tr('nearby_drivers')}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRideOptionCard(ColorScheme cs, RideOption option) {
    return GestureDetector(
      onTap: _showDestinationSearch,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Color(option.color).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Color(option.color).withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(option.icon, color: Color(option.color), size: 24),
            const SizedBox(height: 6),
            Text(option.nameSw,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurface)),
            const SizedBox(height: 2),
            Text(option.price,
              style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.bold)),
            Text(option.time,
              style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(ColorScheme cs, IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverSection(BuildContext context, ColorScheme cs, RideProvider provider) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.driverHome),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: provider.driverOnline
                ? [Colors.green.withValues(alpha: 0.08), Colors.green.withValues(alpha: 0.02)]
                : [cs.error.withValues(alpha: 0.05), cs.surfaceContainerHighest.withValues(alpha: 0.2)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: provider.driverOnline ? Colors.green.withValues(alpha: 0.2) : cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: provider.driverOnline ? Colors.green.withValues(alpha: 0.15) : cs.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  provider.driverOnline ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  key: ValueKey(provider.driverOnline),
                  color: provider.driverOnline ? Colors.green : cs.error, size: 28,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(provider.driverOnline ? context.tr('you_are_online') : context.tr('you_are_offline'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
                  Text(provider.driverOnline ? 'Tap to view driver dashboard' : 'Go online to receive ride requests',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Switch.adaptive(
              value: provider.driverOnline,
              activeColor: Colors.green,
              onChanged: (val) => val ? provider.goOnline() : provider.goOffline(),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
// Destination Search Bottom Sheet
// ──────────────────────────────────────────────────────
class _DestinationSearchSheet extends StatefulWidget {
  final RideApiService apiService;
  final void Function(double lat, double lng, String address) onSelect;

  const _DestinationSearchSheet({required this.apiService, required this.onSelect});

  @override
  State<_DestinationSearchSheet> createState() => _DestinationSearchSheetState();
}

class _DestinationSearchSheetState extends State<_DestinationSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await widget.apiService.geocode(query);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 16),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(
                color: cs.outlineVariant, borderRadius: BorderRadius.circular(2),
              )),
              const SizedBox(height: 20),
              // Search field
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search destination...',
                    prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () { _searchCtrl.clear(); setState(() => _results = []); },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Results
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                                const SizedBox(height: 12),
                                Text(context.tr('search_destination'), style: TextStyle(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final r = _results[i];
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.location_on_rounded, color: cs.primary, size: 20),
                                ),
                                title: Text(r['address'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: cs.onSurface)),
                                trailing: Icon(Icons.arrow_forward_ios, size: 14, color: cs.onSurfaceVariant),
                                onTap: () {
                                  final lat = (r['lat'] as num).toDouble();
                                  final lng = (r['lng'] as num).toDouble();
                                  final addr = r['address'] as String? ?? '';
                                  widget.onSelect(lat, lng, addr);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RideOption {
  final IconData icon;
  final String name;
  final String nameSw;
  final String price;
  final String time;
  final int color;

  RideOption({
    required this.icon,
    required this.name,
    required this.nameSw,
    required this.price,
    required this.time,
    required this.color,
  });
}
