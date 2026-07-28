import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/ride_provider.dart';
import '../../models/ride_models.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../services/ride_api_service.dart';

class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({super.key});

  @override
  State<RideBookingScreen> createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen> {
  GoogleMapController? _mapController;
  LatLng? _pickup;
  LatLng? _dropoff;
  String? _pickupAddress;
  String? _dropoffAddress;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  FareEstimate? _estimate;
  bool _loadingFare = false;
  bool _requesting = false;
  final RideApiService _apiService = RideApiService();

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController ctl) {
    _mapController = ctl;
  }

  void _onMapTap(LatLng pos) async {
    if (_pickup == null) {
      setState(() => _pickup = pos);
      _updateMarkers();
      _reverseGeocode(pos, isPickup: true);
      if (_dropoff != null) _fetchEstimate();
    } else if (_dropoff == null) {
      setState(() => _dropoff = pos);
      _updateMarkers();
      _reverseGeocode(pos, isPickup: false);
      _fetchEstimate();
    }
  }

  Future<void> _reverseGeocode(LatLng pos, {required bool isPickup}) async {
    try {
      final address = await _apiService.reverseGeocode(pos.latitude, pos.longitude);
      if (isPickup) {
        _pickupAddress = address;
      } else {
        _dropoffAddress = address;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchEstimate() async {
    if (_pickup == null || _dropoff == null) return;
    setState(() => _loadingFare = true);
    try {
      final provider = context.read<RideProvider>();
      _estimate = await provider.estimateFare(
        pickupLat: _pickup!.latitude,
        pickupLng: _pickup!.longitude,
        dropoffLat: _dropoff!.latitude,
        dropoffLng: _dropoff!.longitude,
      );
      _fetchPolyline();
    } catch (_) {}
    if (mounted) setState(() => _loadingFare = false);
  }

  Future<void> _fetchPolyline() async {
    if (_pickup == null || _dropoff == null) return;
    try {
      final result = await _apiService.getDirections(
        originLat: _pickup!.latitude,
        originLng: _pickup!.longitude,
        destLat: _dropoff!.latitude,
        destLng: _dropoff!.longitude,
      );
      final points = result['polyline'] as List<dynamic>? ?? [];
      if (points.isNotEmpty) {
        final path = points.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
        setState(() {
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: const PolylineId('route'),
            points: path,
            color: Theme.of(context).colorScheme.primary,
            width: 4,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ));
        });
      }
    } catch (_) {}
  }

  void _updateMarkers() {
    _markers.clear();
    if (_pickup != null) {
      _markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickup!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupAddress),
      ));
    }
    if (_dropoff != null) {
      _markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: _dropoff!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Dropoff', snippet: _dropoffAddress),
      ));
    }
    setState(() {});
  }

  void _reset() {
    setState(() {
      _pickup = null;
      _dropoff = null;
      _pickupAddress = null;
      _dropoffAddress = null;
      _markers.clear();
      _polylines.clear();
      _estimate = null;
    });
  }

  Future<void> _requestRide() async {
    if (_pickup == null || _dropoff == null || _estimate == null) return;
    setState(() => _requesting = true);
    try {
      final provider = context.read<RideProvider>();
      final rideId = await provider.requestRide(
        pickupLat: _pickup!.latitude,
        pickupLng: _pickup!.longitude,
        pickupAddress: _pickupAddress,
        dropoffLat: _dropoff!.latitude,
        dropoffLng: _dropoff!.longitude,
        dropoffAddress: _dropoffAddress,
        distanceKm: _estimate!.distanceKm,
        durationMin: _estimate!.durationMin,
        fare: _estimate!.fare,
      );
      if (rideId != null && mounted) {
        context.pushReplacement('${AppRoutes.rideTracking}/$rideId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(-6.7924, 39.2083),
              zoom: 13,
            ),
            onMapCreated: _onMapCreated,
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: _markers,
            polylines: _polylines,
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.circle, size: 10, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _pickupAddress ?? context.tr('tap_map_dest'),
                                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.square, size: 10, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _dropoffAddress ?? context.tr('set_destination'),
                                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_pickup != null || _dropoff != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: _reset,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(context.tr('reset')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_estimate != null || _loadingFare)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildFareSheet(context, cs),
            ),
        ],
      ),
    );
  }

  Widget _buildFareSheet(BuildContext context, ColorScheme cs) {
    if (_loadingFare) {
      return Container(
        padding: const EdgeInsets.all(24),
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
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final est = _estimate!;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${est.distanceKm} km · ${est.durationMin} min',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Text(
                        '${est.breakdown['baseFare']} + ${est.breakdown['distanceFare']} + ${est.breakdown['timeFare']}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TSh ${est.fare}',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary),
                    ),
                    Text(
                      context.tr('estimated'),
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _requesting ? null : _requestRide,
                icon: _requesting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.directions_car),
                label: Text(_requesting ? context.tr('requesting') : context.tr('request_ride')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
