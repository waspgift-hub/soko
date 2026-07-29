import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
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

class _RideBookingScreenState extends State<RideBookingScreen> with TickerProviderStateMixin {
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
  MapType _mapType = MapType.normal;
  final RideApiService _apiService = RideApiService();
  String _selectedVehicle = 'car';
  late AnimationController _fareSheetCtrl;
  late Animation<Offset> _fareSheetAnim;

  @override
  void initState() {
    super.initState();
    _fareSheetCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fareSheetAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _fareSheetCtrl, curve: Curves.easeOutCubic),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoDetectPickup());
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _fareSheetCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoDetectPickup() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        final loc = LatLng(pos.latitude, pos.longitude);
        setState(() => _pickup = loc);
        _updateMarkers();
        _reverseGeocode(loc, isPickup: true);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 15));
      }
    } catch (_) {}
  }

  void _toggleMapType() => setState(() {
    _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal;
  });

  void _onMapCreated(GoogleMapController ctl) => _mapController = ctl;

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
      if (isPickup) { _pickupAddress = address; } else { _dropoffAddress = address; }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchEstimate() async {
    if (_pickup == null || _dropoff == null) return;
    setState(() => _loadingFare = true);
    _fareSheetCtrl.forward();
    try {
      final provider = context.read<RideProvider>();
      _estimate = await provider.estimateFare(
        pickupLat: _pickup!.latitude, pickupLng: _pickup!.longitude,
        dropoffLat: _dropoff!.latitude, dropoffLng: _dropoff!.longitude,
      );
      _fetchPolyline();
    } catch (_) {}
    if (mounted) setState(() => _loadingFare = false);
  }

  Future<void> _fetchPolyline() async {
    if (_pickup == null || _dropoff == null) return;
    try {
      final result = await _apiService.getDirections(
        originLat: _pickup!.latitude, originLng: _pickup!.longitude,
        destLat: _dropoff!.latitude, destLng: _dropoff!.longitude,
      );
      final points = result['polyline'] as List<dynamic>? ?? [];
      if (points.isNotEmpty) {
        final path = points.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
        setState(() {
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: const PolylineId('route'), points: path,
            color: Theme.of(context).colorScheme.primary, width: 4,
            startCap: Cap.roundCap, endCap: Cap.roundCap,
          ));
        });
      }
    } catch (_) {}
  }

  void _updateMarkers() {
    _markers.clear();
    if (_pickup != null) {
      _markers.add(Marker(
        markerId: const MarkerId('pickup'), position: _pickup!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupAddress),
      ));
    }
    if (_dropoff != null) {
      _markers.add(Marker(
        markerId: const MarkerId('dropoff'), position: _dropoff!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Dropoff', snippet: _dropoffAddress),
      ));
    }
    setState(() {});
  }

  void _reset() {
    setState(() {
      _pickup = null; _dropoff = null;
      _pickupAddress = null; _dropoffAddress = null;
      _markers.clear(); _polylines.clear(); _estimate = null;
    });
  }

  Future<void> _requestRide() async {
    if (_pickup == null || _dropoff == null || _estimate == null) return;
    setState(() => _requesting = true);
    try {
      final provider = context.read<RideProvider>();
      final rideId = await provider.requestRide(
        pickupLat: _pickup!.latitude, pickupLng: _pickup!.longitude,
        pickupAddress: _pickupAddress, dropoffLat: _dropoff!.latitude,
        dropoffLng: _dropoff!.longitude, dropoffAddress: _dropoffAddress,
        distanceKm: _estimate!.distanceKm, durationMin: _estimate!.durationMin,
        fare: _estimate!.fare,
      );
      if (rideId != null && mounted) {
        context.pushReplacement('${AppRoutes.rideTracking}/$rideId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
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
      body: Stack(
        children: [
          GoogleMap(
            mapType: _mapType,
            initialCameraPosition: CameraPosition(
              target: _pickup ?? const LatLng(-6.7924, 39.2083), zoom: 15,
            ),
            onMapCreated: _onMapCreated, onTap: _onMapTap,
            myLocationEnabled: true, myLocationButtonEnabled: false,
            zoomControlsEnabled: false, mapToolbarEnabled: false,
            markers: _markers, polylines: _polylines,
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16, right: 16,
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
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: Icon(Icons.arrow_back, color: cs.onSurface),
                                onPressed: () => context.pop(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(_mapType == MapType.normal ? Icons.satellite_alt : Icons.map,
                                  color: cs.onSurfaceVariant),
                              onPressed: _toggleMapType,
                              tooltip: _mapType == MapType.normal ? 'Satellite' : 'Map',
                            ),
                            const SizedBox(width: 4),
                            Expanded(child: _buildLocationChip(cs, Icons.circle, _pickupAddress ?? context.tr('tap_map_dest'), Colors.green)),
                          ],
                        ),
                        if (_dropoffAddress != null || _dropoff != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                Icon(Icons.square, size: 10, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_dropoffAddress ?? context.tr('set_destination'),
                                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                if (_pickup != null || _dropoff != null)
                                  GestureDetector(
                                    onTap: _reset,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: cs.error.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(context.tr('reset'), style: TextStyle(fontSize: 11, color: cs.error)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_estimate != null || _loadingFare)
            SlideTransition(
              position: _fareSheetAnim,
              child: Align(alignment: Alignment.bottomCenter, child: _buildFareSheet(context, cs)),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationChip(ColorScheme cs, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: cs.onSurface),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildFareSheet(BuildContext context, ColorScheme cs) {
    if (_loadingFare) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final est = _estimate!;
    final fares = est.breakdown['fares'] as Map<String, dynamic>? ?? {};
    final vehicleTypes = [
      {'id': 'bike', 'icon': Icons.pedal_bike, 'label': 'Boda'},
      {'id': 'car', 'icon': Icons.directions_car, 'label': 'Car'},
      {'id': 'van', 'icon': Icons.airport_shuttle, 'label': 'Van'},
      {'id': 'premium', 'icon': Icons.stars, 'label': 'Premium'},
    ];

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
              Container(width: 40, height: 4, decoration: BoxDecoration(
                color: cs.outlineVariant, borderRadius: BorderRadius.circular(2),
              )),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.route, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('${est.distanceKm} km', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: cs.onSurfaceVariant, shape: BoxShape.circle)),
                  Icon(Icons.timer_outlined, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('${est.durationMin} min', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: vehicleTypes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final v = vehicleTypes[i];
                    final isSelected = _selectedVehicle == v['id'];
                    final price = fares[v['id']] as int? ?? 0;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedVehicle = v['id'] as String),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 90,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelected ? cs.primary : Colors.transparent, width: 1.5),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(v['icon'] as IconData, size: 22,
                                color: isSelected ? cs.primary : cs.onSurfaceVariant),
                            const SizedBox(height: 4),
                            Text(v['label'] as String,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                    color: isSelected ? cs.primary : cs.onSurfaceVariant)),
                            Text('TSh $price',
                                style: TextStyle(fontSize: 10, color: isSelected ? cs.primary : cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('estimated'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text('TSh ${fares[_selectedVehicle] ?? est.fare}',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.primary)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _requesting ? null : _requestRide,
                      icon: _requesting
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.directions_car_rounded),
                      label: Text(_requesting ? context.tr('requesting') : context.tr('request_ride')),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
