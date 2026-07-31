import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/ride_models.dart';

class RideApiService {
  static const String _baseUrl = 'https://soko-langu-server.onrender.com/api/ride';
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, String>> _headers() async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final headers = await _headers();
    final resp = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 400) {
      final err = _tryParseError(resp.body);
      throw Exception(err);
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final headers = await _headers();
    final resp = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: headers,
    );
    if (resp.statusCode >= 400) {
      final err = _tryParseError(resp.body);
      throw Exception(err);
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  String _tryParseError(String body) {
    try { return (jsonDecode(body) as Map)['error'] as String? ?? 'Request failed'; }
    catch (_) { return 'Request failed'; }
  }

  FareEstimate _parseFareEstimate(Map<String, dynamic> data, String vehicleType) {
    final fares = data['fares'] as Map<String, dynamic>? ?? {};
    final fare = (fares[vehicleType] as num?)?.toInt() ?? 0;
    return FareEstimate(
      distanceKm: (data['distance'] as num?)?.toDouble() ?? 0,
      durationMin: (data['durationMin'] as num?)?.toInt() ?? 0,
      fare: fare,
      currency: 'TZS',
      breakdown: {
        'distance': data['distance'],
        'durationMin': data['durationMin'],
        'surge': data['surge'],
        'isPeak': data['isPeak'],
        'fares': fares,
        'vehicleTypes': data['vehicleTypes'],
      },
    );
  }

  String _normalizeStatus(String s) {
    if (s == 'requested') return 'REQUESTED';
    if (s == 'searching') return 'SEARCHING';
    if (s == 'driver_found') return 'DRIVER_FOUND';
    if (s == 'driver_accepted') return 'ACCEPTED';
    if (s == 'driver_arriving') return 'DRIVER_ARRIVING';
    if (s == 'driver_arrived') return 'DRIVER_ARRIVED';
    if (s == 'trip_started' || s == 'in_progress') return 'IN_PROGRESS';
    if (s == 'destination_reached') return 'DESTINATION_REACHED';
    if (s == 'trip_completed') return 'COMPLETED';
    if (s == 'payment_completed') return 'PAYMENT_COMPLETED';
    if (s == 'receipt_generated') return 'RECEIPT_GENERATED';
    if (s == 'cancelled') return 'CANCELLED';
    return s.toUpperCase();
  }

  Ride _parseRide(Map<String, dynamic> map, String id) {
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

  Future<FareEstimate> estimateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String vehicleType = 'car',
  }) async {
    final data = await _post('/estimate-fare', {
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'vehicleType': vehicleType,
    });
    return _parseFareEstimate(data, vehicleType);
  }

  Future<String> requestRide({
    required String riderId,
    String? riderName,
    String? riderPhone,
    required double pickupLat,
    required double pickupLng,
    String? pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    String? dropoffAddress,
    double? distanceKm,
    int? durationMin,
    required int fare,
    String vehicleType = 'car',
  }) async {
    final data = await _post('/create-ride-request', {
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'pickupName': pickupAddress ?? 'Pickup',
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'dropoffName': dropoffAddress ?? 'Dropoff',
      'vehicleType': vehicleType,
    });
    return data['requestId'] as String? ?? '';
  }

  Future<Map<String, dynamic>> acceptRide({
    required String rideId,
    required String driverId,
  }) async {
    return _post('/accept-ride', {'requestId': rideId});
  }

  Future<void> arrivedAtPickup({
    required String rideId,
    required String driverId,
  }) async {
    await _post('/driver-arrived', {'requestId': rideId});
  }

  Future<void> startTrip({
    required String rideId,
    required String driverId,
  }) async {
    await _post('/start-trip', {'requestId': rideId});
  }

  Future<Map<String, dynamic>> completeTrip({
    required String rideId,
    required String driverId,
    double? actualDistanceKm,
    int? actualDurationMin,
  }) async {
    return _post('/complete-trip', {
      'requestId': rideId,
      'tripId': '',
    });
  }

  Future<void> cancelRide({
    required String rideId,
    required String userId,
    String? reason,
  }) async {
    await _post('/cancel-ride', {
      'requestId': rideId,
      'reason': reason ?? '',
    });
  }

  Future<Map<String, dynamic>> payRide({
    required String rideId,
    required String riderId,
  }) async {
    return _post('/pay-ride', {'rideId': rideId, 'riderId': riderId});
  }

  Future<void> rateRide({
    required String rideId,
    required String userId,
    required int rating,
    String? comment,
  }) async {
    await _post('/submit-rating', {
      'tripId': rideId,
      'driverId': '',
      'rating': rating,
      'comment': comment ?? '',
    });
  }

  Future<List<NearbyDriver>> getNearbyDrivers({
    required double lat,
    required double lng,
    double radius = 10,
  }) async {
    final data = await _post('/get-nearby-drivers', {
      'latitude': lat,
      'longitude': lng,
      'radiusKm': radius,
    });
    final list = data['drivers'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return NearbyDriver(
        driverId: m['driverId'] as String? ?? '',
        lat: (m['latitude'] as num?)?.toDouble() ?? 0,
        lng: (m['longitude'] as num?)?.toDouble() ?? 0,
        name: m['displayName'] as String? ?? '',
        distanceKm: (m['distance'] as num?)?.toDouble() ?? 0,
        heading: 0,
      );
    }).toList();
  }

  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0,
  }) async {
    await _post('/update-driver-location', {
      'driverId': driverId,
      'latitude': lat,
      'longitude': lng,
      'heading': heading,
    });
  }

  Future<void> setDriverOnline({
    required String driverId,
    required bool online,
  }) async {
    await _post('/update-driver-status', {
      'status': online ? 'online' : 'offline',
    });
  }

  Future<void> registerDriver({
    required String driverId,
    required String type,
    String? model,
    String? color,
    String? regNumber,
    String? licenseNumber,
  }) async {
    final user = _auth.currentUser;
    await _post('/register-driver', {
      'displayName': user?.displayName ?? '',
      'phone': user?.phoneNumber ?? '',
      'vehicleType': type,
      'vehicleModel': model ?? '',
      'vehicleReg': regNumber ?? '',
      'vehicleColor': color ?? '',
    });
  }

  Future<List<Ride>> getDriverRides(String driverId, {int limit = 50}) async {
    final data = await _post('/get-driver-rides', {
      'driverId': driverId,
      'limit': limit,
    });
    final list = data['rides'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return _parseRide(m, m['id'] as String? ?? '');
    }).toList();
  }

  Future<List<Ride>> getRiderRides(String riderId, {int limit = 50}) async {
    final data = await _post('/get-ride-history', {
      'limit': limit,
    });
    final list = data['requests'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return _parseRide(m, m['id'] as String? ?? '');
    }).toList();
  }

  Future<DriverEarnings> getDriverEarnings(String driverId) async {
    final data = await _post('/get-driver-earnings', {'period': 'all'});
    return DriverEarnings(
      totalEarnings: (data['total'] as num?)?.toDouble() ?? 0,
      todayEarnings: (data['today'] as num?)?.toDouble() ?? 0,
      weekEarnings: (data['week'] as num?)?.toDouble() ?? 0,
      completedRides: (data['count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    return _get(
      '/directions?origin=$originLat,$originLng&destination=$destLat,$destLng',
    );
  }

  Future<List<Map<String, dynamic>>> geocode(String query) async {
    final data = await _get('/geocode?query=${Uri.encodeComponent(query)}');
    return (data['results'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    final data = await _get('/reverse-geocode?latlng=$lat,$lng');
    return data['address'] as String? ?? '';
  }
}
