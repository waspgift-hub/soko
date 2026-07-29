import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../providers/ride_provider.dart';
import '../../models/ride_models.dart';
import '../../extensions/context_tr.dart';

class RideTrackingScreen extends StatefulWidget {
  final String rideId;
  const RideTrackingScreen({super.key, required this.rideId});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  Ride? _ride;
  StreamSubscription? _rideSub;
  StreamSubscription? _driverLocSub;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  MapType _mapType = MapType.normal;
  late AnimationController _sheetCtrl;
  late Animation<Offset> _sheetAnim;

  Ride _rideFromFirestore(Map<String, dynamic> map, String id) {
    return Ride(
      rideId: id, riderId: map['riderId'] as String? ?? '',
      riderName: map['riderName'] as String?, riderPhone: map['riderPhone'] as String?,
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
    _sheetCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _sheetAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutCubic),
    );
    _listenToRide();
  }

  @override
  void dispose() {
    _rideSub?.cancel(); _driverLocSub?.cancel();
    _mapController?.dispose(); _sheetCtrl.dispose();
    super.dispose();
  }

  void _listenToRide() {
    _rideSub = FirebaseFirestore.instance.collection('ride_requests').doc(widget.rideId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final ride = _rideFromFirestore(snap.data()!, snap.id);
      if (mounted) { setState(() => _ride = ride); _sheetCtrl.forward(); }
      _updateMarkers(ride);
      if (ride.driverId != null) _listenToDriverLocation(ride.driverId!);
    });
  }

  void _listenToDriverLocation(String driverId) {
    _driverLocSub?.cancel();
    _driverLocSub = FirebaseFirestore.instance.collection('ride_driver_locations').doc(driverId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['latitude'] != null && data['longitude'] != null) {
        final loc = LatLng((data['latitude'] as num).toDouble(), (data['longitude'] as num).toDouble());
        if (mounted) _updateDriverMarker(loc);
      }
    });
  }

  void _updateMarkers(Ride ride) {
    _markers.clear();
    _markers.add(Marker(markerId: const MarkerId('pickup'), position: LatLng(ride.pickup.lat, ride.pickup.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen), infoWindow: InfoWindow(title: 'Pickup', snippet: ride.pickup.address)));
    _markers.add(Marker(markerId: const MarkerId('dropoff'), position: LatLng(ride.dropoff.lat, ride.dropoff.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), infoWindow: InfoWindow(title: 'Dropoff', snippet: ride.dropoff.address)));
  }

  void _updateDriverMarker(LatLng loc) {
    _markers.removeWhere((m) => m.markerId.value == 'driver');
    _markers.add(Marker(markerId: const MarkerId('driver'), position: loc,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: const InfoWindow(title: 'Driver')));
    _mapController?.animateCamera(CameraUpdate.newLatLng(loc));
    setState(() {});
  }

  void _toggleMapType() => setState(() => _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal);

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(context.tr('cancel_ride')), content: Text(context.tr('cancel_confirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('no'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          child: Text(context.tr('yes'))),
      ],
    ));
    if (confirmed == true) {
      await context.read<RideProvider>().cancelRide(widget.rideId);
      if (mounted) context.pop();
    }
  }

  Future<void> _payRide() async {
    final ok = await context.read<RideProvider>().payRide(widget.rideId);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('payment_successful')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: _mapType,
            initialCameraPosition: CameraPosition(
              target: _ride != null ? LatLng(_ride!.pickup.lat, _ride!.pickup.lng) : const LatLng(-6.7924, 39.2083), zoom: 14,
            ),
            onMapCreated: (ctl) => _mapController = ctl,
            myLocationEnabled: true, myLocationButtonEnabled: false,
            zoomControlsEnabled: false, markers: _markers, polylines: _polylines,
          ),
          Positioned(
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
                            onPressed: () { context.read<RideProvider>().clearCurrentRide(); context.pop(); },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: Icon(_mapType == MapType.normal ? Icons.satellite_alt : Icons.map, color: cs.onSurfaceVariant),
                            onPressed: _toggleMapType,
                          ),
                        ),
                        if (_ride != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  _statusDot(_statusColor(_ride!.status, cs)),
                                  const SizedBox(width: 6),
                                  Text(_statusLabel(_ride!.status, context), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_ride != null)
            SlideTransition(
              position: _sheetAnim,
              child: Align(alignment: Alignment.bottomCenter, child: _buildStatusSheet(context, cs, _ride!, user)),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'REQUESTED': return Colors.orange;
      case 'ACCEPTED': return cs.primary;
      case 'DRIVER_ARRIVED': return Colors.green;
      case 'IN_PROGRESS': return cs.primary;
      case 'COMPLETED': return Colors.green;
      case 'PAYMENT_COMPLETED': return Colors.green;
      case 'CANCELLED': return cs.error;
      default: return cs.onSurfaceVariant;
    }
  }

  String _statusLabel(String status, BuildContext context) {
    switch (status) {
      case 'REQUESTED': return context.tr('waiting_driver');
      case 'ACCEPTED': return context.tr('driver_on_way');
      case 'DRIVER_ARRIVED': return 'Driver arrived';
      case 'IN_PROGRESS': return context.tr('trip_in_progress');
      case 'COMPLETED': return context.tr('trip_completed');
      case 'PAYMENT_COMPLETED': return 'Paid';
      case 'CANCELLED': return context.tr('ride_cancelled');
      default: return status;
    }
  }

  Widget _statusDot(Color color) => Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  Widget _buildStatusSheet(BuildContext context, ColorScheme cs, Ride ride, User? user) {
    final isRider = ride.riderId == user?.uid;
    final statusColor = _statusColor(ride.status, cs);

    return Container(
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
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_statusIcon(ride.status), color: statusColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_statusLabel(ride.status, context),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: cs.onSurface)),
                        Text('TSh ${ride.finalFare ?? ride.fare} · ${ride.distanceKm} km · ${ride.durationMin} min',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _locationTile(cs, Icons.circle, ride.pickup.address, Colors.green),
              const SizedBox(height: 10),
              _locationTile(cs, Icons.square, ride.dropoff.address, Colors.red),
              const SizedBox(height: 20),
              if (ride.status == 'REQUESTED' && isRider)
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: _cancelRide, icon: const Icon(Icons.cancel_outlined),
                  label: Text(context.tr('cancel_ride')),
                  style: OutlinedButton.styleFrom(foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
              if (ride.status == 'COMPLETED' && isRider && ride.driverId != null)
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: _payRide, icon: const Icon(Icons.payment),
                  label: Text(context.tr('pay_now')),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
              if (ride.status == 'PAYMENT_COMPLETED' && isRider && ride.rating == null)
                _buildRatingSection(context, cs),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'REQUESTED': return Icons.hourglass_empty;
      case 'ACCEPTED': return Icons.directions_car_rounded;
      case 'DRIVER_ARRIVED': return Icons.check_circle;
      case 'IN_PROGRESS': return Icons.navigation;
      case 'COMPLETED': return Icons.flag;
      case 'PAYMENT_COMPLETED': return Icons.paid;
      case 'CANCELLED': return Icons.cancel;
      default: return Icons.info;
    }
  }

  Widget _locationTile(ColorScheme cs, IconData icon, String address, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          child: Icon(icon, size: 12, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(address, style: TextStyle(fontSize: 13, color: cs.onSurface, height: 1.3),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildRatingSection(BuildContext context, ColorScheme cs) {
    int ratingVal = 5;
    return StatefulBuilder(
      builder: (ctx, setInnerState) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Text(context.tr('rate_driver'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) {
              return IconButton(
                icon: Icon(i < ratingVal ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber, size: 34),
                onPressed: () => setInnerState(() => ratingVal = i + 1),
              );
            })),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await context.read<RideProvider>().rateRide(widget.rideId, ratingVal);
                  if (mounted) setState(() {});
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(context.tr('submit')),
              ),
            ),
          ],
        );
      },
    );
  }
}
