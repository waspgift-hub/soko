import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ride_models.dart';
import '../services/ride_api_service.dart';

enum RideTab { rider, driver }

class RideProvider extends ChangeNotifier {
  final RideApiService _api = RideApiService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  RideTab _activeTab = RideTab.rider;
  RideTab get activeTab => _activeTab;
  set activeTab(RideTab t) {
    _activeTab = t;
    notifyListeners();
  }

  // Rider state
  FareEstimate? _fareEstimate;
  FareEstimate? get fareEstimate => _fareEstimate;

  Ride? _currentRide;
  Ride? get currentRide => _currentRide;

  List<Ride> _riderRides = [];
  List<Ride> get riderRides => _riderRides;

  // Driver state
  bool _driverOnline = false;
  bool get driverOnline => _driverOnline;

  bool _isDriver = false;
  bool get isDriver => _isDriver;

  List<Ride> _driverRides = [];
  List<Ride> get driverRides => _driverRides;

  DriverEarnings? _earnings;
  DriverEarnings? get earnings => _earnings;

  List<NearbyDriver> _nearbyDrivers = [];
  List<NearbyDriver> get nearbyDrivers => _nearbyDrivers;

  // Loading/error
  bool _loading = false;
  bool get loading => _loading;
  String? _error;
  String? get error => _error;

  StreamSubscription? _rideSub;
  StreamSubscription? _driverRidesSub;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> checkDriverStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await _firestore.collection('ride_driver_locations').doc(user.uid).get();
    if (doc.exists) {
      _driverOnline = doc.data()?['status'] == 'online';
    }
    final driverDoc = await _firestore.collection('ride_drivers').doc(user.uid).get();
    _isDriver = driverDoc.exists;
    notifyListeners();
  }

  // --- Rider methods ---
  Future<FareEstimate?> estimateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _fareEstimate = await _api.estimateFare(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
      );
      return _fareEstimate;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> requestRide({
    required double pickupLat,
    required double pickupLng,
    String? pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    String? dropoffAddress,
    double? distanceKm,
    int? durationMin,
    required int fare,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rideId = await _api.requestRide(
        riderId: user.uid,
        riderName: user.displayName,
        riderPhone: user.phoneNumber,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        pickupAddress: pickupAddress,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
        dropoffAddress: dropoffAddress,
        distanceKm: distanceKm,
        durationMin: durationMin,
        fare: fare,
      );
      _listenToRide(rideId);
      return rideId;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> payRide(String rideId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.payRide(rideId: rideId, riderId: user.uid);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> rateRide(String rideId, int rating, {String? comment}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.rateRide(rideId: rideId, userId: user.uid, rating: rating, comment: comment);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelRide(String rideId, {String? reason}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.cancelRide(rideId: rideId, userId: user.uid, reason: reason);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Ride _rideFromFirestore(Map<String, dynamic> map, String id) {
    return Ride(
      rideId: id,
      riderId: map['riderId'] as String? ?? '',
      riderName: map['riderName'] as String?,
      riderPhone: map['riderPhone'] as String?,
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
      ratingComment: map['ratingComment'] as String?,
      cancelReason: map['cancelReason'] as String?,
      cancelledBy: map['cancelBy'] as String?,
      paymentMethod: map['paymentMethod'] as String?,
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

  void _listenToRide(String rideId) {
    _rideSub?.cancel();
    _rideSub = _firestore.collection('ride_requests').doc(rideId).snapshots().listen((snap) {
      if (snap.exists) {
        _currentRide = _rideFromFirestore(snap.data()!, snap.id);
        notifyListeners();
      }
    });
  }

  void stopListening() {
    _rideSub?.cancel();
    _rideSub = null;
    _driverRidesSub?.cancel();
    _driverRidesSub = null;
  }

  void clearCurrentRide() {
    _currentRide = null;
    _fareEstimate = null;
    _rideSub?.cancel();
    _rideSub = null;
    notifyListeners();
  }

  // --- Driver methods ---
  Future<bool> goOnline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.setDriverOnline(driverId: user.uid, online: true);
      _driverOnline = true;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> goOffline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.setDriverOnline(driverId: user.uid, online: false);
      _driverOnline = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> acceptRide(String rideId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    _loading = true;
    notifyListeners();
    try {
      await _api.acceptRide(rideId: rideId, driverId: user.uid);
      _listenToRide(rideId);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> arrivedAtPickup(String rideId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.arrivedAtPickup(rideId: rideId, driverId: user.uid);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> startTrip(String rideId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.startTrip(rideId: rideId, driverId: user.uid);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> completeTrip(String rideId, {double? distance, int? duration}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _api.completeTrip(
        rideId: rideId,
        driverId: user.uid,
        actualDistanceKm: distance,
        actualDurationMin: duration,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> updateLocation(double lat, double lng) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _api.updateDriverLocation(driverId: user.uid, lat: lat, lng: lng);
    } catch (_) {}
  }

  Future<bool> registerDriver({
    required String type,
    String? model,
    String? color,
    String? regNumber,
    String? licenseNumber,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    _loading = true;
    notifyListeners();
    try {
      await _api.registerDriver(
        driverId: user.uid,
        type: type,
        model: model,
        color: color,
        regNumber: regNumber,
        licenseNumber: licenseNumber,
      );
      _isDriver = true;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchNearbyDrivers(double lat, double lng) async {
    try {
      _nearbyDrivers = await _api.getNearbyDrivers(lat: lat, lng: lng);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchDriverRides() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      _driverRides = await _api.getDriverRides(user.uid);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchRiderRides() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      _riderRides = await _api.getRiderRides(user.uid);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchEarnings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      _earnings = await _api.getDriverEarnings(user.uid);
      notifyListeners();
    } catch (_) {}
  }

  void listenToRideRequests() {
    _driverRidesSub?.cancel();
    _driverRidesSub = _firestore
        .collection('ride_requests')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
