import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/soko_vibe_loading.dart';

class LocationMapWidget extends StatefulWidget {
  final double? targetLat;
  final double? targetLng;
  final String? targetLabel;
  final double height;
  final bool showDistance;
  final bool interactive;
  final bool draggablePin;
  final void Function(double lat, double lng)? onLocationChanged;

  const LocationMapWidget({
    super.key,
    required this.targetLat,
    required this.targetLng,
    this.targetLabel,
    this.height = 180,
    this.showDistance = true,
    this.interactive = false,
    this.draggablePin = false,
    this.onLocationChanged,
  });

  @override
  State<LocationMapWidget> createState() => _LocationMapWidgetState();
}

class _LocationMapWidgetState extends State<LocationMapWidget> {
  GoogleMapController? _mapController;
  LatLng? _myLocation;
  MapType _mapType = MapType.normal;
  double? _distanceKm;
  double? _pinLat;
  double? _pinLng;

  @override
  void initState() {
    super.initState();
    _pinLat = widget.targetLat;
    _pinLng = widget.targetLng;
    _detectMyLocation();
  }

  Future<void> _detectMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
        _calculateDistance();
      }
    } catch (_) {}
  }

  void _calculateDistance() {
    final tLat = _pinLat ?? widget.targetLat;
    final tLng = _pinLng ?? widget.targetLng;
    if (_myLocation == null || tLat == null || tLng == null) return;
    final distance = Geolocator.distanceBetween(
      _myLocation!.latitude,
      _myLocation!.longitude,
      tLat,
      tLng,
    );
    setState(() => _distanceKm = distance / 1000);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasTarget = (_pinLat != null && _pinLng != null) || (widget.targetLat != null && widget.targetLng != null);
    final targetPos = _pinLat != null && _pinLng != null
        ? LatLng(_pinLat!, _pinLng!)
        : (widget.targetLat != null && widget.targetLng != null
            ? LatLng(widget.targetLat!, widget.targetLng!)
            : null);

    final markers = <Marker>{};
    if (targetPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('target'),
        position: targetPos,
        draggable: widget.draggablePin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: widget.targetLabel ?? 'Location'),
        onDragEnd: widget.draggablePin
            ? (pos) {
                setState(() {
                  _pinLat = pos.latitude;
                  _pinLng = pos.longitude;
                });
                widget.onLocationChanged?.call(pos.latitude, pos.longitude);
              }
            : null,
      ));
    }
    if (_myLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: _myLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You'),
      ));
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GoogleMap(
            mapType: _mapType,
            initialCameraPosition: CameraPosition(
              target: targetPos ?? _myLocation ?? const LatLng(-6.7924, 39.2083),
              zoom: 12,
            ),
            onMapCreated: (ctl) {
              _mapController = ctl;
              if (targetPos != null && _myLocation != null) {
                _fitBoth();
              }
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: widget.interactive,
            tiltGesturesEnabled: false,
            rotateGesturesEnabled: false,
            markers: markers,
          ),
          if (widget.showDistance && _distanceKm != null)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.straighten, size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      _distanceKm! < 1
                          ? '${(_distanceKm! * 1000).round()} m'
                          : '${_distanceKm!.toStringAsFixed(1)} km',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                  ],
                ),
              ),
            ),
          if (_myLocation == null && _distanceKm == null && hasTarget)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SokoVibeThreeDotLoader(size: 16, dotSize: 4, color: cs.primary),
              ),
            ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Row(
              children: [
                if (_myLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                      ),
                      child: IconButton(
                        tooltip: 'My location',
                        icon: Icon(Icons.my_location, size: 18, color: cs.primary),
                        onPressed: () => _goToMyLocation(),
                      ),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _mapType == MapType.normal ? Icons.satellite : Icons.map,
                      size: 18, color: cs.onSurface,
                    ),
                    onPressed: () => setState(() {
                      _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    if (_myLocation == null) return;
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_myLocation!, 16),
    );
  }

  Future<void> _fitBoth() async {
    final tLat = _pinLat ?? widget.targetLat;
    final tLng = _pinLng ?? widget.targetLng;
    if (_myLocation == null || tLat == null || tLng == null) return;
    final target = LatLng(tLat, tLng);
    final bounds = LatLngBounds(
      southwest: LatLng(
        min(_myLocation!.latitude, target.latitude),
        min(_myLocation!.longitude, target.longitude),
      ),
      northeast: LatLng(
        max(_myLocation!.latitude, target.latitude),
        max(_myLocation!.longitude, target.longitude),
      ),
    );
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }
}
