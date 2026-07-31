import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/ride_provider.dart';
import '../../models/ride_models.dart';
import '../../extensions/context_tr.dart';
import '../../services/ride_api_service.dart';

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

  // Driver tracking
  LatLng? _driverPosition;
  LatLng? _lastDriverPosition;
  LatLng? _targetDriverPosition;
  Timer? _driverAnimTimer;
  int _etaSeconds = 0;
  Timer? _etaTimer;
  String? _driverName;
  String? _driverPhone;
  String? _driverVehicle;

  final RideApiService _apiService = RideApiService();

  Ride _rideFromFirestore(Map<String, dynamic> map, String id) {
    return Ride(
      rideId: id, riderId: map['riderId'] as String? ?? '',
      riderName: map['riderName'] as String?, riderPhone: map['riderPhone'] as String?,
      pickup: RideLocation(
        lat: (map['pickupLat'] as num?)?.toDouble() ?? 0,
        lng: (map['pickupLng'] as num?)?.toDouble() ?? 0,
        address: map['pickupName'] as String? ?? '',
      ),
      dropoff: RideLocation(
        lat: (map['dropoffLat'] as num?)?.toDouble() ?? 0,
        lng: (map['dropoffLng'] as num?)?.toDouble() ?? 0,
        address: map['dropoffName'] as String? ?? '',
      ),
      distanceKm: (map['distance'] as num?)?.toDouble() ?? 0,
      durationMin: (map['durationMin'] as num?)?.toInt() ?? 0,
      fare: (map['fare'] as num?)?.toInt() ?? 0,
      finalFare: (map['finalFare'] as num?)?.toInt(),
      status: _normalizeStatus(map['status'] as String? ?? 'REQUESTED'),
      driverId: map['assignedDriverId'] as String?,
      driverPayout: (map['driverPayout'] as num?)?.toInt(),
      rating: (map['rating'] as num?)?.toInt(),
    );
  }

  String _normalizeStatus(String s) {
    if (s == 'requested') return 'REQUESTED';
    if (s == 'driver_accepted') return 'ACCEPTED';
    if (s == 'driver_arrived') return 'DRIVER_ARRIVED';
    if (s == 'trip_started' || s == 'in_progress') return 'IN_PROGRESS';
    if (s == 'trip_completed') return 'COMPLETED';
    if (s == 'payment_completed') return 'PAYMENT_COMPLETED';
    if (s == 'cancelled') return 'CANCELLED';
    return s.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _sheetCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _sheetAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutCubic),
    );
    _listenToRide();
    _startEtaTimer();
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _driverLocSub?.cancel();
    _driverAnimTimer?.cancel();
    _etaTimer?.cancel();
    _mapController?.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  void _listenToRide() {
    _rideSub = FirebaseFirestore.instance.collection('ride_requests').doc(widget.rideId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final ride = _rideFromFirestore(snap.data()!, snap.id);
      if (mounted) {
        setState(() => _ride = ride);
        _sheetCtrl.forward();
      }
      _updateMarkers(ride);
      if (ride.driverId != null) _listenToDriverLocation(ride.driverId!);
      if (_driverName == null && ride.driverId != null) _fetchDriverInfo(ride.driverId!);
      _updateEta();
    });
  }

  Future<void> _fetchDriverInfo(String driverId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('ride_drivers').doc(driverId).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _driverName = data['displayName'] as String? ?? 'Driver';
            _driverPhone = data['phone'] as String?;
            _driverVehicle = '${data['vehicleModel'] ?? ''} ${data['vehicleReg'] ?? ''}'.trim();
          });
        }
      }
    } catch (_) {}
  }

  void _listenToDriverLocation(String driverId) {
    _driverLocSub?.cancel();
    _driverLocSub = FirebaseFirestore.instance.collection('ride_driver_locations').doc(driverId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['latitude'] != null && data['longitude'] != null) {
        final loc = LatLng((data['latitude'] as num).toDouble(), (data['longitude'] as num).toDouble());
        if (mounted) _animateDriverMarker(loc);
      }
    });
  }

  void _animateDriverMarker(LatLng newLoc) {
    _lastDriverPosition = _driverPosition;
    _targetDriverPosition = newLoc;
    if (_lastDriverPosition == null) {
      _driverPosition = newLoc;
      _updateDriverMarker(newLoc);
      return;
    }
    _driverAnimTimer?.cancel();
    final startPos = _driverPosition!;
    final endPos = newLoc;
    final distance = _haversine(startPos.latitude, startPos.longitude, endPos.latitude, endPos.longitude);
    final steps = (distance * 50).clamp(5, 30).toInt();
    int step = 0;
    _driverAnimTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      step++;
      final t = step / steps;
      final lat = startPos.latitude + (endPos.latitude - startPos.latitude) * t;
      final lng = startPos.longitude + (endPos.longitude - startPos.longitude) * t;
      _updateDriverMarker(LatLng(lat, lng));
      if (step >= steps) {
        timer.cancel();
        _driverPosition = endPos;
        _updateDriverMarker(endPos);
      }
    });
    _driverPosition = newLoc;
    _updateEta();
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  void _updateEta() {
    if (_ride == null || _driverPosition == null) return;
    final target = _ride!.status == 'ACCEPTED' || _ride!.status == 'DRIVER_FOUND' || _ride!.status == 'DRIVER_ARRIVED'
        ? LatLng(_ride!.pickup.lat, _ride!.pickup.lng)
        : LatLng(_ride!.dropoff.lat, _ride!.dropoff.lng);
    final dist = _haversine(
      _driverPosition!.latitude, _driverPosition!.longitude,
      target.latitude, target.longitude,
    );
    final eta = (dist / 30 * 3600).round(); // assume 30 km/h avg
    if (mounted) setState(() => _etaSeconds = eta);
  }

  void _startEtaTimer() {
    _etaTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateEta());
  }

  void _updateMarkers(Ride ride) {
    _markers.clear();
    _markers.add(Marker(
      markerId: const MarkerId('pickup'),
      position: LatLng(ride.pickup.lat, ride.pickup.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: context.tr('pickup_label'), snippet: ride.pickup.address),
    ));
    _markers.add(Marker(
      markerId: const MarkerId('dropoff'),
      position: LatLng(ride.dropoff.lat, ride.dropoff.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: context.tr('dropoff_label'), snippet: ride.dropoff.address),
    ));
    _fitBounds();
  }

  void _updateDriverMarker(LatLng loc) {
    _markers.removeWhere((m) => m.markerId.value == 'driver');
    _markers.add(Marker(
      markerId: const MarkerId('driver'),
      position: loc,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: InfoWindow(
        title: _driverName ?? 'Driver',
        snippet: _driverVehicle ?? '',
      ),
    ));
    setState(() {});
  }

  void _fitBounds() {
    if (_ride == null) return;
    final all = <LatLng>[
      LatLng(_ride!.pickup.lat, _ride!.pickup.lng),
      LatLng(_ride!.dropoff.lat, _ride!.dropoff.lng),
    ];
    if (_driverPosition != null) all.add(_driverPosition!);
    double minLat = all.first.latitude, maxLat = all.first.latitude;
    double minLng = all.first.longitude, maxLng = all.first.longitude;
    for (final p in all) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      80,
    ));
  }

  void _toggleMapType() => setState(() => _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal);

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.tr('cancel_ride')),
        content: Text(context.tr('cancel_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('no'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(context.tr('yes')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<RideProvider>().cancelRide(widget.rideId);
      if (mounted) context.pop();
    }
  }

  Future<void> _payRide() async {
    final ok = await context.read<RideProvider>().payRide(widget.rideId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? context.tr('payment_successful') : context.tr('payment_failed')),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _callDriver() async {
    if (_driverPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('no_phone_number'))));
      return;
    }
    final uri = Uri.parse('tel:$_driverPhone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _sosAlert() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.tr('sos_emergency')),
        content: Text(context.tr('sos_alert_message')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.tr('send_sos')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try { await launchUrl(Uri.parse('tel:112')); } catch (_) {}
      try {
        final user = FirebaseAuth.instance.currentUser;
        await FirebaseFirestore.instance.collection('sos_alerts').add({
          'userId': user?.uid ?? '',
          'rideId': widget.rideId,
          'pickupLat': _ride?.pickup.lat,
          'pickupLng': _ride?.pickup.lng,
          'dropoffLat': _ride?.dropoff.lat,
          'dropoffLng': _ride?.dropoff.lng,
          'driverId': _ride?.driverId ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': 'admin',
          'title': 'SOS Alert',
          'body': 'Rider ${user?.uid ?? ''} needs help on ride ${widget.rideId}',
          'type': 'sos',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('sos_alert_sent')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
      ));
    }
  }

  String _formatEta(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final min = (seconds / 60).round();
    if (min < 60) return '$min min';
    final h = (min / 60).floor();
    final m = min % 60;
    return '${h}h ${m}m';
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
              target: _ride != null ? LatLng(_ride!.pickup.lat, _ride!.pickup.lng) : const LatLng(-6.7924, 39.2083),
              zoom: 14,
            ),
            onMapCreated: (ctl) {
              _mapController = ctl;
              if (_ride != null) Future.microtask(_fitBounds);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
          ),
          // Top bar
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
                                  Text(_statusLabel(_ride!.status, context),
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
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
          // ETA badge on map
          if (_etaSeconds > 0 && _ride != null && (_ride!.status == 'ACCEPTED' || _ride!.status == 'DRIVER_FOUND' || _ride!.status == 'DRIVER_ARRIVED' || _ride!.status == 'IN_PROGRESS'))
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(_formatEta(_etaSeconds),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.primary)),
                  ],
                ),
              ),
            ),
          // SOS button
          if (_ride != null && _ride!.status != 'COMPLETED' && _ride!.status != 'PAYMENT_COMPLETED' && _ride!.status != 'CANCELLED')
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.42,
              right: 16,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: Material(
                      color: Colors.red,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sosAlert,
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(Icons.warning_rounded, color: Colors.white, size: 26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(context.tr('sos_button'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.error)),
                ],
              ),
            ),
          // Bottom status sheet
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
      case 'SEARCHING': return Colors.orange;
      case 'DRIVER_FOUND': return cs.primary;
      case 'ACCEPTED': return cs.primary;
      case 'DRIVER_ARRIVED': return Colors.green;
      case 'IN_PROGRESS': return Colors.blue;
      case 'COMPLETED': return Colors.green;
      case 'PAYMENT_COMPLETED': return Colors.green;
      case 'CANCELLED': return cs.error;
      default: return cs.onSurfaceVariant;
    }
  }

  String _statusLabel(String status, BuildContext context) {
    switch (status) {
      case 'REQUESTED': return context.tr('waiting_driver');
      case 'SEARCHING': return context.tr('waiting_driver');
      case 'DRIVER_FOUND': return context.tr('driver_on_way');
      case 'ACCEPTED': return context.tr('driver_on_way');
      case 'DRIVER_ARRIVED': return context.tr('driver_arrived_label');
      case 'IN_PROGRESS': return context.tr('trip_in_progress');
      case 'COMPLETED': return context.tr('trip_completed');
      case 'PAYMENT_COMPLETED': return context.tr('paid_status');
      case 'CANCELLED': return context.tr('ride_cancelled');
      default: return status;
    }
  }

  Widget _statusDot(Color color) => Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  Widget _buildStatusSheet(BuildContext context, ColorScheme cs, Ride ride, User? user) {
    final isRider = ride.riderId == user?.uid;
    final statusColor = _statusColor(ride.status, cs);
    final showEta = _etaSeconds > 0 && (ride.status == 'ACCEPTED' || ride.status == 'DRIVER_FOUND' || ride.status == 'DRIVER_ARRIVED' || ride.status == 'IN_PROGRESS');

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
              // Status header with driver info
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [statusColor, statusColor.withValues(alpha: 0.7)]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Icon(_statusIcon(ride.status), color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_statusLabel(ride.status, context),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: cs.onSurface)),
                            if (showEta) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_formatEta(_etaSeconds),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                              ),
                            ],
                          ],
                        ),
                        if (ride.status == 'IN_PROGRESS')
                          Text('${ride.distanceKm} km · ${ride.durationMin} min',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        if (_driverName != null && (ride.status == 'ACCEPTED' || ride.status == 'DRIVER_FOUND' || ride.status == 'DRIVER_ARRIVED' || ride.status == 'IN_PROGRESS'))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.person, size: 14, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(_driverName!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                if (_driverVehicle != null && _driverVehicle!.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.directions_car, size: 12, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text(_driverVehicle!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Driver call button if driver assigned
              if (_driverPhone != null && (ride.status == 'ACCEPTED' || ride.status == 'DRIVER_FOUND' || ride.status == 'DRIVER_ARRIVED' || ride.status == 'IN_PROGRESS'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _callDriver,
                      icon: const Icon(Icons.phone_rounded, size: 18),
                      label: Text(context.trParams('call_driver', {'name': _driverName ?? context.tr('unknown_driver')})),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              // Locations
              _locationTile(cs, Icons.circle, ride.pickup.address, Colors.green),
              const SizedBox(height: 8),
              _locationTile(cs, Icons.square, ride.dropoff.address, Colors.red),
              const SizedBox(height: 20),
              // Action buttons
              if ((ride.status == 'REQUESTED' || ride.status == 'SEARCHING' || ride.status == 'DRIVER_FOUND' || ride.status == 'ACCEPTED') && isRider)
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: _cancelRide,
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(context.tr('cancel_ride')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )),
              if (ride.status == 'COMPLETED' && isRider && ride.driverId != null)
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: _payRide,
                  icon: const Icon(Icons.payment),
                  label: Text(context.tr('pay_now')),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
      case 'SEARCHING': return Icons.hourglass_empty;
      case 'DRIVER_FOUND': return Icons.directions_car_rounded;
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
        Container(margin: const EdgeInsets.only(top: 4), child: Icon(icon, size: 12, color: color)),
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
