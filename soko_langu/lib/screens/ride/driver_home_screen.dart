import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/ride_provider.dart';
import '../../models/ride_models.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  StreamSubscription<Ride>? _pendingRideSub;
  Ride? _pendingRequest;
  Timer? _locationTimer;
  bool _showRequest = false;
  MapType _mapType = MapType.normal;
  late AnimationController _requestSlideCtrl;
  late Animation<Offset> _requestSlideAnim;

  Ride _rideFromFirestore(Map<String, dynamic> map, String id) {
    return Ride(
      rideId: id, riderId: map['riderId'] as String? ?? '', riderName: map['riderName'] as String?, riderPhone: map['riderPhone'] as String?,
      pickup: RideLocation(lat: (map['pickupLat'] as num?)?.toDouble() ?? 0, lng: (map['pickupLng'] as num?)?.toDouble() ?? 0, address: map['pickupName'] as String? ?? ''),
      dropoff: RideLocation(lat: (map['dropoffLat'] as num?)?.toDouble() ?? 0, lng: (map['dropoffLng'] as num?)?.toDouble() ?? 0, address: map['dropoffName'] as String? ?? ''),
      distanceKm: (map['distance'] as num?)?.toDouble() ?? 0, durationMin: (map['durationMin'] as num?)?.toInt() ?? 0,
      fare: (map['fare'] as num?)?.toInt() ?? 0, status: _normalizeStatus(map['status'] as String? ?? 'REQUESTED'),
      driverId: map['assignedDriverId'] as String?,
    );
  }

  String _normalizeStatus(String s) {
    if (s == 'requested') return 'REQUESTED'; if (s == 'driver_accepted') return 'ACCEPTED';
    if (s == 'driver_arrived') return 'DRIVER_ARRIVED';
    if (s == 'trip_started' || s == 'in_progress') return 'IN_PROGRESS';
    if (s == 'trip_completed') return 'COMPLETED'; if (s == 'payment_completed') return 'PAYMENT_COMPLETED';
    if (s == 'cancelled') return 'CANCELLED'; return s.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _requestSlideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _requestSlideAnim = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _requestSlideCtrl, curve: Curves.easeOutCubic),
    );
    _checkRegistration();
    _listenToPendingRides();
    _startLocationUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnMyLocation());
  }

  @override
  void dispose() {
    _pendingRideSub?.cancel(); _locationTimer?.cancel();
    _mapController?.dispose(); _requestSlideCtrl.dispose();
    super.dispose();
  }

  Future<void> _centerOnMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
    } catch (_) {}
  }

  Future<void> _checkRegistration() async {
    final provider = context.read<RideProvider>();
    await provider.checkDriverStatus();
    if (!provider.isDriver && mounted) {
      final shouldRegister = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.tr('register_driver')),
        content: Text(context.tr('driver_register_prompt')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('later'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('register'))),
        ],
      ));
      if (shouldRegister == true && mounted) context.push(AppRoutes.driverRegister);
    }
  }

  void _listenToPendingRides() {
    _pendingRideSub = FirebaseFirestore.instance.collection('ride_requests')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty ? _rideFromFirestore(snap.docs.first.data(), snap.docs.first.id) : null)
        .where((r) => r != null).cast<Ride>()
        .listen((ride) {
          if (mounted && context.read<RideProvider>().driverOnline) {
            setState(() { _pendingRequest = ride; _showRequest = true; });
            _requestSlideCtrl.forward();
          }
        });
  }

  void _toggleMapType() => setState(() => _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal);

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final provider = context.read<RideProvider>();
      if (!provider.driverOnline) return;
      try {
        final pos = await Geolocator.getCurrentPosition();
        await provider.updateLocation(pos.latitude, pos.longitude);
      } catch (_) {}
    });
  }

  void _acceptRide() async {
    if (_pendingRequest == null) return;
    final ok = await context.read<RideProvider>().acceptRide(_pendingRequest!.rideId);
    if (ok && mounted) setState(() { _showRequest = false; _pendingRequest = null; });
  }

  void _rejectRide() => setState(() { _showRequest = false; _pendingRequest = null; });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<RideProvider>();

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: _mapType,
            initialCameraPosition: const CameraPosition(target: LatLng(-6.7924, 39.2083), zoom: 14),
            onMapCreated: (ctl) => _mapController = ctl,
            myLocationEnabled: true, myLocationButtonEnabled: false,
            zoomControlsEnabled: false, mapToolbarEnabled: false,
          ),
          _buildTopBar(context, cs, provider),
          if (_showRequest && _pendingRequest != null)
            SlideTransition(position: _requestSlideAnim, child: _buildIncomingRequest(context, cs, _pendingRequest!, provider)),
          if (provider.currentRide?.isActive == true && provider.currentRide?.driverId == FirebaseAuth.instance.currentUser?.uid)
            _buildActiveRideSheet(context, cs, provider.currentRide!),
          _buildBottomControls(context, cs, provider),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ColorScheme cs, RideProvider provider) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16,
      child: SafeArea(
        bottom: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: cs.onSurface),
                      onPressed: () async {
                        if (provider.driverOnline) await provider.goOffline();
                        if (mounted) context.pop();
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(_mapType == MapType.normal ? Icons.satellite_alt : Icons.map, color: cs.onSurfaceVariant),
                    onPressed: _toggleMapType,
                  ),
                  const Spacer(),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: provider.driverOnline ? Colors.green.withValues(alpha: 0.1) : cs.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: provider.driverOnline ? Colors.green : cs.error)),
                        const SizedBox(width: 6),
                        Text(provider.driverOnline ? context.tr('online') : context.tr('offline'),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context, ColorScheme cs, RideProvider provider) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 24, left: 16, right: 16,
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(provider.driverOnline ? context.tr('you_are_online') : context.tr('you_are_offline'),
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface)),
                              Text(provider.driverOnline ? context.tr('drivers_online_subtitle') : context.tr('drivers_offline_subtitle'),
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _quickButton(cs, Icons.trending_up, context.tr('earnings'), () => context.push(AppRoutes.driverEarnings))),
                        const SizedBox(width: 8),
                        Expanded(child: _quickButton(cs, Icons.history_rounded, context.tr('ride_history'), () => context.push(AppRoutes.rideHistory))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickButton(ColorScheme cs, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: cs.primary, size: 18),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingRequest(BuildContext context, ColorScheme cs, Ride ride, RideProvider provider) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 80, left: 16, right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.7)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.directions_car_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('incoming_request'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface)),
                        Text(ride.riderName ?? context.tr('rider'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _locationRow(cs, Icons.circle, ride.pickup.address, Colors.green),
                const SizedBox(height: 6),
                _locationRow(cs, Icons.square, ride.dropoff.address, Colors.red),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('TSh ${ride.fare}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
                    const Spacer(),
                    Text('${ride.distanceKm} km · ${ride.durationMin} min', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: provider.loading ? null : _rejectRide,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error, side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(context.tr('reject')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: provider.loading ? null : _acceptRide,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: provider.loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(context.tr('accept')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationRow(ColorScheme cs, IconData icon, String address, Color color) {
    return Row(
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(address, style: TextStyle(fontSize: 13, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildActiveRideSheet(BuildContext context, ColorScheme cs, Ride ride) {
    final provider = context.read<RideProvider>();
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
                Row(
                  children: [
                    Icon(Icons.directions_car_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(context.tr('active_ride'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface)),
                  ],
                ),
                const SizedBox(height: 12),
                _locationRow(cs, Icons.circle, ride.pickup.address, Colors.green),
                const SizedBox(height: 4),
                _locationRow(cs, Icons.square, ride.dropoff.address, Colors.red),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('TSh ${ride.fare}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
                    const Spacer(),
                    Text('${ride.distanceKm} km', style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 14),
                if (ride.status == 'ACCEPTED')
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: () => provider.arrivedAtPickup(ride.rideId),
                    icon: const Icon(Icons.location_on), label: Text(context.tr('arrived')),
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  )),
                if (ride.status == 'DRIVER_ARRIVED')
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: () => provider.startTrip(ride.rideId),
                    icon: const Icon(Icons.play_arrow_rounded), label: Text(context.tr('start_trip')),
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  )),
                if (ride.status == 'IN_PROGRESS')
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: () => provider.completeTrip(ride.rideId),
                    icon: const Icon(Icons.flag), label: Text(context.tr('end_trip')),
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
