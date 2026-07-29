import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/ride_provider.dart';

import 'package:go_router/go_router.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';

class RideHomeScreen extends StatefulWidget {
  const RideHomeScreen({super.key});

  @override
  State<RideHomeScreen> createState() => _RideHomeScreenState();
}

class _RideHomeScreenState extends State<RideHomeScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  LatLng? _currentLocation;
  MapType _mapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RideProvider>().clearCurrentRide();
      _detectLocation();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
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
      }
    } catch (_) {}
  }

  void _onMapCreated(GoogleMapController ctl) {
    _mapController = ctl;
    if (_currentLocation != null) {
      ctl.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLocation!, 15),
      );
    }
  }

  void _toggleMapType() {
    setState(() {
      _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal;
    });
  }

  void _openBooking() {
    context.push(AppRoutes.rideBooking);
  }

  void _openRideHistory() {
    context.push(AppRoutes.rideHistory);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<RideProvider>();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          GoogleMap(
            mapType: _mapType,
            initialCameraPosition: CameraPosition(
              target: _currentLocation ?? const LatLng(-6.7924, 39.2083),
              zoom: 15,
            ),
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            markers: _markers,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 72,
            left: 16,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              color: cs.surface,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openBooking,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.search, color: cs.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('where_to'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.tr('tap_map_dest'),
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 100,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(_mapType == MapType.normal ? Icons.satellite : Icons.map, color: cs.onSurface),
                    onPressed: _toggleMapType,
                    tooltip: _mapType == MapType.normal ? 'Satellite' : 'Map',
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(Icons.my_location, color: cs.onSurface),
                    onPressed: () {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          _currentLocation ?? const LatLng(-6.7924, 39.2083),
                          15,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(Icons.history, color: cs.onSurface),
                    onPressed: _openRideHistory,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomSheet(context, cs, isDark, provider, user),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet(BuildContext context, ColorScheme cs, bool isDark, RideProvider provider, User? user) {
    final isDriver = provider.isDriver;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDriver) ...[
                _buildDriverToggle(context, cs, provider, user),
              ] else ...[
                _buildRiderActions(context, cs, provider),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverToggle(BuildContext context, ColorScheme cs, RideProvider provider, User? user) {
    final online = provider.driverOnline;

    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: online ? Colors.green.withValues(alpha: 0.1) : cs.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                online ? Icons.check_circle : Icons.cancel,
                color: online ? Colors.green : cs.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    online ? context.tr('you_are_online') : context.tr('you_are_offline'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    online ? context.tr('drivers_online_subtitle') : context.tr('drivers_offline_subtitle'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Switch(
              value: online,
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
        const SizedBox(height: 12),
        if (online) ...[
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => context.push(AppRoutes.driverEarnings),
              icon: const Icon(Icons.trending_up),
              label: Text(context.tr('earnings')),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.rideHome),
              icon: const Icon(Icons.person_outline),
              label: Text(context.tr('rider_mode')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRiderActions(BuildContext context, ColorScheme cs, RideProvider provider) {
    return Column(
      children: [
        if (provider.isDriver)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                provider.activeTab = RideTab.driver;
                context.push(AppRoutes.driverHome);
              },
              icon: const Icon(Icons.directions_car),
              label: Text(context.tr('driver_mode')),
            ),
          ),
      ],
    );
  }
}
