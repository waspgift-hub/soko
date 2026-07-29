import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../models/ride_models.dart';

class RideCloudService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _base = '${ApiConfig.baseUrl}/api/ride';

  Future<Map<String, String>> _headers() async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> _post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _headers();
    final response = await http.post(
      Uri.parse('$_base/$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode >= 400) {
      final err = _tryParseError(response.body);
      throw Exception(err);
    }
    return jsonDecode(response.body);
  }

  String _tryParseError(String body) {
    try { return (jsonDecode(body) as Map)['error'] as String? ?? 'Request failed'; }
    catch (_) { return 'Request failed'; }
  }

  Future<FareEstimate> estimateFare({
    required double pickupLat, required double pickupLng,
    required double dropoffLat, required double dropoffLng,
    String vehicleType = 'car',
  }) async {
    final data = await _post('estimate-fare', {
      'pickupLat': pickupLat, 'pickupLng': pickupLng,
      'dropoffLat': dropoffLat, 'dropoffLng': dropoffLng,
      'vehicleType': vehicleType,
    });
    return FareEstimate.fromMap(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> createRideRequest({
    required double pickupLat, required double pickupLng,
    String? pickupName, required double dropoffLat, required double dropoffLng,
    String? dropoffName, String vehicleType = 'car', String? idempotencyKey,
  }) async {
    return await _post('create-ride-request', {
      'pickupLat': pickupLat, 'pickupLng': pickupLng,
      'pickupName': pickupName ?? 'Pickup Location',
      'dropoffLat': dropoffLat, 'dropoffLng': dropoffLng,
      'dropoffName': dropoffName ?? 'Dropoff Location',
      'vehicleType': vehicleType,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> acceptRide(String requestId) async {
    return await _post('accept-ride', {'requestId': requestId}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectRide(String requestId) async {
    return await _post('reject-ride', {'requestId': requestId}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> driverArrived(String requestId) async {
    return await _post('driver-arrived', {'requestId': requestId}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startTrip(String requestId) async {
    return await _post('start-trip', {'requestId': requestId}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> completeTrip({String? requestId, String? tripId}) async {
    return await _post('complete-trip', {
      if (requestId != null) 'requestId': requestId,
      if (tripId != null) 'tripId': tripId,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelRide({required String requestId, String? reason}) async {
    return await _post('cancel-ride', {
      'requestId': requestId,
      if (reason != null) 'reason': reason,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitRating({
    required String tripId, required String driverId,
    required int rating, String? comment,
  }) async {
    return await _post('submit-rating', {
      'tripId': tripId, 'driverId': driverId, 'rating': rating,
      if (comment != null) 'comment': comment,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDriverProfile(String? driverId) async {
    return await _post('get-driver-profile', {
      if (driverId != null) 'driverId': driverId,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDriverEarnings(String? driverId) async {
    return await _post('get-driver-earnings', {
      if (driverId != null) 'driverId': driverId,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateDriverStatus({required String status, double? latitude, double? longitude}) async {
    return await _post('update-driver-status', {
      'status': status,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registerDriver({
    required String displayName, required String phone,
    required String vehicleModel, required String vehicleReg,
    required String licenseNumber, String? vehicleColor,
    String vehicleType = 'car',
  }) async {
    return await _post('register-driver', {
      'displayName': displayName, 'phone': phone,
      'vehicleModel': vehicleModel, 'vehicleReg': vehicleReg,
      'licenseNumber': licenseNumber,
      if (vehicleColor != null) 'vehicleColor': vehicleColor,
      'vehicleType': vehicleType,
    }) as Map<String, dynamic>;
  }

  Future<void> updateDriverLocation({
    required double latitude, required double longitude,
    double heading = 0, double speed = 0, double accuracy = 0,
  }) async {
    await _post('update-driver-location', {
      'latitude': latitude, 'longitude': longitude,
      'heading': heading, 'speed': speed, 'accuracy': accuracy,
    });
  }

  Future<Map<String, dynamic>> getDriverLocation(String driverId) async {
    return await _post('get-driver-location', {'driverId': driverId}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getNearbyDrivers({
    required double latitude, required double longitude, double radiusKm = 5,
  }) async {
    return await _post('get-nearby-drivers', {
      'latitude': latitude, 'longitude': longitude, 'radiusKm': radiusKm,
    }) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getActiveRequest() async {
    return await _post('get-active-request', {}) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getRideHistory({int limit = 20, String? lastDocId}) async {
    return await _post('get-ride-history', {
      'limit': limit,
      if (lastDocId != null) 'lastDocId': lastDocId,
    }) as Map<String, dynamic>;
  }

  Future<void> updateTripRoute({
    required String tripId, required double latitude, required double longitude,
  }) async {
    await _post('update-trip-route', {
      'tripId': tripId, 'latitude': latitude, 'longitude': longitude,
    });
  }
}
