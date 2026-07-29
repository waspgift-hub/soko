import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../providers/ride_provider.dart';
import '../../models/ride_models.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Ride>? _pendingRideSub;
  Ride? _pendingRequest;
  Timer? _locationTimer;
  bool _showRequest = false;
  MapType _mapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    _checkRegistration();
    _listenToPendingRides();
    _startLocationUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnMyLocation());
  }

  Future<void> _centerOnMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkRegistration() async {
    final provider = context.read<RideProvider>();
    await provider.checkDriverStatus();
    if (!provider.isDriver && mounted) {
      final shouldRegister = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('register_driver')),
          content: Text(context.tr('driver_register_prompt')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('later'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('register'))),
          ],
        ),
      );
      if (shouldRegister == true && mounted) {
        context.push(AppRoutes.driverRegister);
      }
    }
  }

  void _listenToPendingRides() {
    _pendingRideSub = FirebaseFirestore.instance
        .collection('rides')
        .where('status', isEqualTo: 'REQUESTED')
        .snapshots()
        .map((snap) {
          if (snap.docs.isNotEmpty) {
            return Ride.fromMap(snap.docs.first.data(), snap.docs.first.id);
          }
          return null;
        })
        .where((r) => r != null)
        .cast<Ride>()
        .listen((ride) {
          if (mounted && context.read<RideProvider>().driverOnline) {
            setState(() {
              _pendingRequest = ride;
              _showRequest = true;
            });
          }
        });
  }

  void _toggleMapType() {
    setState(() {
      _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal;
    });
  }

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final provider = context.read<RideProvider>();
      if (!provider.driverOnline) return;
      try {
        final pos = await Geolocator.getCurrentPosition();
        await provider.updateLocation(pos.latitude, pos.longitude);
        if (mounted) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
          );
        }
      } catch (_) {}
    });
  }

  void _acceptRide() async {
    if (_pendingRequest == null) return;
    final provider = context.read<RideProvider>();
    final ok = await provider.acceptRide(_pendingRequest!.rideId);
    if (ok && mounted) {
      setState(() => _showRequest = false);
    }
  }

  void _rejectRide() {
    setState(() {
      _showRequest = false;
      _pendingRequest = null;
    });
  }

  @override
  void dispose() {
    _pendingRideSub?.cancel();
    _locationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<RideProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          GoogleMap(
            mapType: _mapType,
            initialCameraPosition: const CameraPosition(
              target: LatLng(-6.7924, 39.2083),
              zoom: 14,
            ),
            onMapCreated: (ctl) => _mapController = ctl,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                          onPressed: () async {
                            if (provider.driverOnline) {
                              await provider.goOffline();
                            }
                            if (mounted) context.pop();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(_mapType == MapType.normal ? Icons.satellite : Icons.map,
                              color: cs.onSurface),
                          onPressed: _toggleMapType,
                          tooltip: _mapType == MapType.normal ? 'Satellite' : 'Map',
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: provider.driverOnline ? Colors.green : cs.error,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              provider.driverOnline ? context.tr('online') : context.tr('offline'),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider.driverOnline
                                    ? context.tr('you_are_online')
                                    : context.tr('you_are_offline'),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
                              ),
                              Text(
                                provider.driverOnline
                                    ? context.tr('drivers_online_subtitle')
                                    : context.tr('drivers_offline_subtitle'),
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: provider.driverOnline,
                          activeColor: Colors.green,
                          onChanged: (val) {
                            if (val) {
                              provider.goOnline();
                            } else {
                              provider.goOffline();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _quickActionCard(
                          cs: cs,
                          icon: Icons.trending_up,
                          label: context.tr('earnings'),
                          onTap: () => context.push(AppRoutes.driverEarnings),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _quickActionCard(
                          cs: cs,
                          icon: Icons.history,
                          label: context.tr('ride_history'),
                          onTap: () => context.push(AppRoutes.rideHistory),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (_showRequest && _pendingRequest != null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: _buildIncomingRequest(context, cs, _pendingRequest!, provider),
            ),
          if (provider.currentRide?.isActive == true && provider.currentRide?.driverId == FirebaseAuth.instance.currentUser?.uid)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActiveRideSheet(context, cs, provider.currentRide!),
            ),
        ],
      ),
    );
  }

  Widget _quickActionCard({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: cs.primary, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingRequest(BuildContext context, ColorScheme cs, Ride ride, RideProvider provider) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      color: cs.surface,
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.directions_car, color: cs.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('incoming_request'),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    Text(ride.riderName ?? context.tr('rider'),
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _locationRow(cs, Icons.circle, ride.pickup.address, Colors.green),
            const SizedBox(height: 6),
            _locationRow(cs, Icons.square, ride.dropoff.address, Colors.red),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('TSh ${ride.fare}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
                const Spacer(),
                Text('${ride.distanceKm} km', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: provider.loading ? null : _rejectRide,
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    child: Text(context.tr('reject')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: provider.loading ? null : _acceptRide,
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
    );
  }

  Widget _locationRow(ColorScheme cs, IconData icon, String address, Color color) {
    return Row(
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(address, style: TextStyle(fontSize: 13, color: cs.onSurface),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildActiveRideSheet(BuildContext context, ColorScheme cs, Ride ride) {
    final provider = context.read<RideProvider>();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('active_ride'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            _locationRow(cs, Icons.circle, ride.pickup.address, Colors.green),
            const SizedBox(height: 4),
            _locationRow(cs, Icons.square, ride.dropoff.address, Colors.red),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('TSh ${ride.fare}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
                const Spacer(),
                Text('${ride.distanceKm} km', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            if (ride.status == 'ACCEPTED')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await provider.arrivedAtPickup(ride.rideId);
                  },
                  icon: const Icon(Icons.location_on),
                  label: Text(context.tr('arrived')),
                ),
              ),
            if (ride.status == 'DRIVER_ARRIVED')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await provider.startTrip(ride.rideId);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(context.tr('start_trip')),
                ),
              ),
            if (ride.status == 'IN_PROGRESS')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await provider.completeTrip(ride.rideId);
                  },
                  icon: const Icon(Icons.flag),
                  label: Text(context.tr('end_trip')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
