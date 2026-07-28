import 'dart:async';
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

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  GoogleMapController? _mapController;
  Ride? _ride;
  StreamSubscription? _rideSub;
  StreamSubscription? _driverLocSub;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _listenToRide();
  }

  void _listenToRide() {
    _rideSub = FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.rideId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final ride = Ride.fromMap(snap.data()!, snap.id);
      if (mounted) setState(() => _ride = ride);
      _updateMarkers(ride);
      if (ride.driverId != null) {
        _listenToDriverLocation(ride.driverId!);
      }
    });
  }

  void _listenToDriverLocation(String driverId) {
    _driverLocSub?.cancel();
    _driverLocSub = FirebaseFirestore.instance
        .collection('driver_locations')
        .doc(driverId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['lat'] != null && data['lng'] != null) {
        final loc = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
        if (mounted) _updateDriverMarker(loc);
      }
    });
  }

  void _updateMarkers(Ride ride) {
    _markers.clear();
    _markers.add(Marker(
      markerId: const MarkerId('pickup'),
      position: LatLng(ride.pickup.lat, ride.pickup.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: 'Pickup', snippet: ride.pickup.address),
    ));
    _markers.add(Marker(
      markerId: const MarkerId('dropoff'),
      position: LatLng(ride.dropoff.lat, ride.dropoff.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: 'Dropoff', snippet: ride.dropoff.address),
    ));
  }

  void _updateDriverMarker(LatLng loc) {
    _markers.removeWhere((m) => m.markerId.value == 'driver');
    _markers.add(Marker(
      markerId: const MarkerId('driver'),
      position: loc,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: const InfoWindow(title: 'Driver'),
    ));
    setState(() {});
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _driverLocSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('cancel_ride')),
        content: Text(context.tr('cancel_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('no'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('yes'))),
        ],
      ),
    );
    if (confirmed == true) {
      final provider = context.read<RideProvider>();
      await provider.cancelRide(widget.rideId);
      if (mounted) context.pop();
    }
  }

  Future<void> _payRide() async {
    final provider = context.read<RideProvider>();
    final ok = await provider.payRide(widget.rideId);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('payment_successful'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _ride != null
                  ? LatLng(_ride!.pickup.lat, _ride!.pickup.lng)
                  : const LatLng(-6.7924, 39.2083),
              zoom: 14,
            ),
            onMapCreated: (ctl) => _mapController = ctl,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: cs.onSurface),
                      onPressed: () {
                        context.read<RideProvider>().clearCurrentRide();
                        context.pop();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _ride != null ? _buildStatusSheet(context, cs, _ride!, user) : const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSheet(BuildContext context, ColorScheme cs, Ride ride, User? user) {
    final isRider = ride.riderId == user?.uid;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusHeader(context, cs, ride),
            const SizedBox(height: 12),
            _buildLocationRow(cs, Icons.circle, ride.pickup.address, Colors.green),
            const SizedBox(height: 8),
            _buildLocationRow(cs, Icons.square, ride.dropoff.address, Colors.red),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('TSh ${ride.finalFare ?? ride.fare}',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.primary)),
                const Spacer(),
                Text('${ride.distanceKm} km · ${ride.durationMin} min',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            if (ride.status == 'REQUESTED' && isRider) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancelRide,
                  icon: const Icon(Icons.cancel),
                  label: Text(context.tr('cancel_ride')),
                  style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                ),
              ),
            ],
            if (ride.status == 'COMPLETED' && isRider && ride.driverId != null) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _payRide,
                  icon: const Icon(Icons.payment),
                  label: Text(context.tr('pay_now')),
                ),
              ),
            ],
            if (ride.status == 'PAID' && isRider && ride.rating == null) ...[
              _buildRatingSection(context, cs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusHeader(BuildContext context, ColorScheme cs, Ride ride) {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (ride.status) {
      case 'REQUESTED':
        statusText = context.tr('waiting_driver');
        statusIcon = Icons.hourglass_empty;
        statusColor = Colors.orange;
      case 'ACCEPTED':
        statusText = context.tr('driver_on_way');
        statusIcon = Icons.directions_car;
        statusColor = cs.primary;
      case 'DRIVER_ARRIVED':
        statusText = 'Driver arrived';
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
      case 'IN_PROGRESS':
        statusText = context.tr('trip_in_progress');
        statusIcon = Icons.navigation;
        statusColor = cs.primary;
      case 'COMPLETED':
        statusText = context.tr('trip_completed');
        statusIcon = Icons.flag;
        statusColor = Colors.green;
      case 'PAID':
        statusText = 'Paid';
        statusIcon = Icons.paid;
        statusColor = Colors.green;
      case 'CANCELLED':
        statusText = context.tr('ride_cancelled');
        statusIcon = Icons.cancel;
        statusColor = cs.error;
      default:
        statusText = ride.status;
        statusIcon = Icons.info;
        statusColor = cs.onSurface;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(statusText,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ],
    );
  }

  Widget _buildLocationRow(ColorScheme cs, IconData icon, String address, Color color) {
    return Row(
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(address, style: TextStyle(fontSize: 13, color: cs.onSurface),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildRatingSection(BuildContext context, ColorScheme cs) {
    int ratingVal = 5;
    return StatefulBuilder(
      builder: (ctx, setInnerState) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Text(context.tr('rate_driver'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return IconButton(
                  icon: Icon(
                    i < ratingVal ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed: () => setInnerState(() => ratingVal = i + 1),
                );
              }),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final provider = context.read<RideProvider>();
                  await provider.rateRide(widget.rideId, ratingVal);
                  if (mounted) setState(() {});
                },
                child: Text(context.tr('submit')),
              ),
            ),
          ],
        );
      },
    );
  }
}
