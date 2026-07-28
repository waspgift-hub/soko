import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ride_models.dart';

class RideApiService {
  static const String _baseUrl = 'https://soko-langu-server.onrender.com';

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 400) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? 'Request failed');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
    );
    if (resp.statusCode >= 400) {
      final err = jsonDecode(resp.body);
      throw Exception(err['error'] ?? 'Request failed');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<FareEstimate> estimateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final data = await _post('/api/rides/estimate', {
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
    });
    return FareEstimate.fromMap(data);
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
  }) async {
    final data = await _post('/api/rides/request', {
      'riderId': riderId,
      'riderName': riderName ?? '',
      'riderPhone': riderPhone ?? '',
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'pickupAddress': pickupAddress ?? '',
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'dropoffAddress': dropoffAddress ?? '',
      'distanceKm': distanceKm,
      'durationMin': durationMin,
      'fare': fare,
    });
    return data['rideId'] as String;
  }

  Future<Map<String, dynamic>> acceptRide({
    required String rideId,
    required String driverId,
  }) async {
    return _post('/api/rides/accept', {'rideId': rideId, 'driverId': driverId});
  }

  Future<void> arrivedAtPickup({
    required String rideId,
    required String driverId,
  }) async {
    await _post('/api/rides/arrived', {'rideId': rideId, 'driverId': driverId});
  }

  Future<void> startTrip({
    required String rideId,
    required String driverId,
  }) async {
    await _post('/api/rides/start', {'rideId': rideId, 'driverId': driverId});
  }

  Future<Map<String, dynamic>> completeTrip({
    required String rideId,
    required String driverId,
    double? actualDistanceKm,
    int? actualDurationMin,
  }) async {
    return _post('/api/rides/complete', {
      'rideId': rideId,
      'driverId': driverId,
      'actualDistanceKm': actualDistanceKm,
      'actualDurationMin': actualDurationMin,
    });
  }

  Future<void> cancelRide({
    required String rideId,
    required String userId,
    String? reason,
  }) async {
    await _post('/api/rides/cancel', {
      'rideId': rideId,
      'userId': userId,
      'reason': reason ?? '',
    });
  }

  Future<Map<String, dynamic>> payRide({
    required String rideId,
    required String riderId,
  }) async {
    return _post('/api/rides/pay', {'rideId': rideId, 'riderId': riderId});
  }

  Future<void> rateRide({
    required String rideId,
    required String userId,
    required int rating,
    String? comment,
  }) async {
    await _post('/api/rides/rate', {
      'rideId': rideId,
      'userId': userId,
      'rating': rating,
      'comment': comment ?? '',
    });
  }

  Future<List<NearbyDriver>> getNearbyDrivers({
    required double lat,
    required double lng,
    double radius = 10,
  }) async {
    final data = await _get('/api/rides/nearby-drivers?lat=$lat&lng=$lng&radius=$radius');
    final list = data['drivers'] as List<dynamic>? ?? [];
    return list.map((e) => NearbyDriver.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0,
  }) async {
    await _post('/api/driver/location', {
      'driverId': driverId,
      'lat': lat,
      'lng': lng,
      'heading': heading,
    });
  }

  Future<void> setDriverOnline({
    required String driverId,
    required bool online,
  }) async {
    await _post('/api/driver/online', {'driverId': driverId, 'online': online});
  }

  Future<void> registerDriver({
    required String driverId,
    required String type,
    String? model,
    String? color,
    String? regNumber,
    String? licenseNumber,
  }) async {
    await _post('/api/driver/register', {
      'driverId': driverId,
      'type': type,
      'model': model ?? '',
      'color': color ?? '',
      'regNumber': regNumber ?? '',
      'licenseNumber': licenseNumber ?? '',
    });
  }

  Future<List<Ride>> getDriverRides(String driverId, {int limit = 50}) async {
    final data = await _get('/api/driver/rides/$driverId?limit=$limit');
    final list = data['rides'] as List<dynamic>? ?? [];
    return list.map((e) => Ride.fromMap(e as Map<String, dynamic>, e['rideId'] as String? ?? '')).toList();
  }

  Future<List<Ride>> getRiderRides(String riderId, {int limit = 50}) async {
    final data = await _get('/api/rider/rides/$riderId?limit=$limit');
    final list = data['rides'] as List<dynamic>? ?? [];
    return list.map((e) => Ride.fromMap(e as Map<String, dynamic>, e['rideId'] as String? ?? '')).toList();
  }

  Future<DriverEarnings> getDriverEarnings(String driverId) async {
    final data = await _get('/api/driver/earnings/$driverId');
    return DriverEarnings.fromMap(data);
  }

  Future<Map<String, dynamic>> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    return _get(
      '/api/rides/directions?origin=$originLat,$originLng&destination=$destLat,$destLng',
    );
  }

  Future<List<Map<String, dynamic>>> geocode(String query) async {
    final data = await _get('/api/rides/geocode?query=${Uri.encodeComponent(query)}');
    return (data['results'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    final data = await _get('/api/rides/reverse-geocode?latlng=$lat,$lng');
    return data['address'] as String? ?? '';
  }
}
