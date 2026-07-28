class RideLocation {
  final double lat;
  final double lng;
  final String address;

  RideLocation({required this.lat, required this.lng, this.address = ''});

  factory RideLocation.fromMap(Map<String, dynamic> map) {
    return RideLocation(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      address: map['address'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng, 'address': address};
}

class Ride {
  final String rideId;
  final String riderId;
  final String? riderName;
  final String? riderPhone;
  final RideLocation pickup;
  final RideLocation dropoff;
  final double distanceKm;
  final int durationMin;
  final int fare;
  final int? finalFare;
  final String status;
  final String? driverId;
  final int? driverPayout;
  final int? rating;
  final String? ratingComment;
  final String? cancelReason;
  final String? cancelledBy;
  final String? paymentMethod;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;

  Ride({
    required this.rideId,
    required this.riderId,
    this.riderName,
    this.riderPhone,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.durationMin,
    required this.fare,
    this.finalFare,
    required this.status,
    this.driverId,
    this.driverPayout,
    this.rating,
    this.ratingComment,
    this.cancelReason,
    this.cancelledBy,
    this.paymentMethod,
    this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.paidAt,
    this.cancelledAt,
  });

  factory Ride.fromMap(Map<String, dynamic> map, String rideId) {
    return Ride(
      rideId: rideId,
      riderId: map['riderId'] as String? ?? '',
      riderName: map['riderName'] as String?,
      riderPhone: map['riderPhone'] as String?,
      pickup: map['pickup'] != null
          ? RideLocation.fromMap(map['pickup'] as Map<String, dynamic>)
          : RideLocation(lat: 0, lng: 0),
      dropoff: map['dropoff'] != null
          ? RideLocation.fromMap(map['dropoff'] as Map<String, dynamic>)
          : RideLocation(lat: 0, lng: 0),
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
      durationMin: (map['durationMin'] as num?)?.toInt() ?? 0,
      fare: (map['fare'] as num?)?.toInt() ?? 0,
      finalFare: (map['finalFare'] as num?)?.toInt(),
      status: map['status'] as String? ?? 'REQUESTED',
      driverId: map['driverId'] as String?,
      driverPayout: (map['driverPayout'] as num?)?.toInt(),
      rating: (map['rating'] as num?)?.toInt(),
      ratingComment: map['ratingComment'] as String?,
      cancelReason: map['cancelReason'] as String?,
      cancelledBy: map['cancelledBy'] as String?,
      paymentMethod: map['paymentMethod'] as String?,
      createdAt: map['createdAt'] != null ? _parseTimestamp(map['createdAt']) : null,
      acceptedAt: map['acceptedAt'] != null ? _parseTimestamp(map['acceptedAt']) : null,
      startedAt: map['startedAt'] != null ? _parseTimestamp(map['startedAt']) : null,
      completedAt: map['completedAt'] != null ? _parseTimestamp(map['completedAt']) : null,
      paidAt: map['paidAt'] != null ? _parseTimestamp(map['paidAt']) : null,
      cancelledAt: map['cancelledAt'] != null ? _parseTimestamp(map['cancelledAt']) : null,
    );
  }

  static DateTime? _parseTimestamp(dynamic ts) {
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is Map) return null;
    return null;
  }

  bool get isActive =>
      status == 'REQUESTED' || status == 'ACCEPTED' || status == 'DRIVER_ARRIVED' || status == 'IN_PROGRESS';
}

class NearbyDriver {
  final String driverId;
  final double lat;
  final double lng;
  final String name;
  final double distanceKm;
  final double heading;

  NearbyDriver({
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.name,
    required this.distanceKm,
    required this.heading,
  });

  factory NearbyDriver.fromMap(Map<String, dynamic> map) {
    return NearbyDriver(
      driverId: map['driverId'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      name: map['name'] as String? ?? '',
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DriverEarnings {
  final double totalEarnings;
  final double todayEarnings;
  final double weekEarnings;
  final int completedRides;

  DriverEarnings({
    required this.totalEarnings,
    required this.todayEarnings,
    required this.weekEarnings,
    required this.completedRides,
  });

  factory DriverEarnings.fromMap(Map<String, dynamic> map) {
    return DriverEarnings(
      totalEarnings: (map['totalEarnings'] as num?)?.toDouble() ?? 0,
      todayEarnings: (map['todayEarnings'] as num?)?.toDouble() ?? 0,
      weekEarnings: (map['weekEarnings'] as num?)?.toDouble() ?? 0,
      completedRides: (map['completedRides'] as num?)?.toInt() ?? 0,
    );
  }
}

class FareEstimate {
  final double distanceKm;
  final int durationMin;
  final int fare;
  final String currency;
  final Map<String, dynamic> breakdown;

  FareEstimate({
    required this.distanceKm,
    required this.durationMin,
    required this.fare,
    required this.currency,
    required this.breakdown,
  });

  factory FareEstimate.fromMap(Map<String, dynamic> map) {
    return FareEstimate(
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
      durationMin: (map['durationMin'] as num?)?.toInt() ?? 0,
      fare: (map['fare'] as num?)?.toInt() ?? 0,
      currency: map['currency'] as String? ?? 'TZS',
      breakdown: map['breakdown'] as Map<String, dynamic>? ?? {},
    );
  }
}


