import 'package:cloud_firestore/cloud_firestore.dart';

/// Banner types supported by the platform.
enum BannerType {
  sponsoredAd,
  promotion,
  newFeature,
  platformAnnouncement,
  adminConfigured,
}

/// Banner placement locations in the app.
enum BannerPlacement {
  homeFeed,
  searchResults,
  categoryPage,
  productDetail,
  sellerDashboard,
  profilePage,
  checkoutFlow,
  ordersPage,
  notificationsPage,
  wishlistPage,
  flashSalePage,
  musicFeed,
  chatList,
}

/// Banner status lifecycle.
enum BannerStatus {
  draft,
  scheduled,
  active,
  paused,
  expired,
  archived,
}

/// Target audience for banner display.
enum BannerAudience {
  allUsers,
  signedInUsers,
  buyersOnly,
  sellersOnly,
  businessAccounts,
  kycApproved,
  blueTickSellers,
  nonBlueTickSellers,
}

/// Banner destination types.
enum BannerDestinationType {
  productDetail,
  categoryPage,
  sellerProfile,
  externalUrl,
  deepLink,
  flashSalePage,
  addProduct,
  boostProduct,
  kycPage,
  notificationsPage,
}

/// A single banner campaign managed by admins.
class BannerCampaign {
  BannerCampaign({
    required this.id,
    required this.title,
    required this.mainText,
    this.subtitle,
    required this.type,
    this.imageUrl,
    this.videoUrl,
    required this.ctaLabel,
    required this.destinationType,
    required this.destinationValue,
    required this.placement,
    required this.priority,
    required this.startDate,
    required this.endDate,
    required this.targetAudience,
    this.deviceTargeting,
    required this.status,
    this.impressionLimit,
    this.clickLimit,
    this.sponsorName,
    this.sponsorInfo,
    this.localization,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.impressionCount = 0,
    this.clickCount = 0,
  });

  final String id;
  final String title;
  final String mainText;
  final String? subtitle;
  final BannerType type;
  final String? imageUrl;
  final String? videoUrl;
  final String ctaLabel;
  final BannerDestinationType destinationType;
  final String destinationValue;
  final BannerPlacement placement;
  final int priority;
  final DateTime startDate;
  final DateTime endDate;
  final BannerAudience targetAudience;
  final List<String>? deviceTargeting; // e.g., ['mobile', 'tablet', 'desktop']
  final BannerStatus status;
  final int? impressionLimit;
  final int? clickLimit;
  final String? sponsorName;
  final String? sponsorInfo;
  final Map<String, BannerLocalization>? localization;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final int impressionCount;
  final int clickCount;

  /// Creates a BannerCampaign from a Firestore document.
  factory BannerCampaign.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return BannerCampaign(
      id: doc.id,
      title: data['title'] ?? '',
      mainText: data['mainText'] ?? '',
      subtitle: data['subtitle'],
      type: BannerType.values.byName(data['type'] ?? 'adminConfigured'),
      imageUrl: data['imageUrl'],
      videoUrl: data['videoUrl'],
      ctaLabel: data['ctaLabel'] ?? '',
      destinationType: BannerDestinationType.values.byName(
        data['destinationType'] ?? 'externalUrl'),
      destinationValue: data['destinationValue'] ?? '',
      placement: BannerPlacement.values.byName(
        data['placement'] ?? 'homeFeed'),
      priority: data['priority'] ?? 0,
      startDate: (data['startDate'] as Timestamp?)?.toDate() ??
          DateTime.now().subtract(const Duration(days: 1)),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 365)),
      targetAudience: BannerAudience.values.byName(
        data['targetAudience'] ?? 'allUsers'),
      deviceTargeting: (data['deviceTargeting'] as List<dynamic>?)?.cast<String>(),
      status: BannerStatus.values.byName(data['status'] ?? 'draft'),
      impressionLimit: data['impressionLimit'],
      clickLimit: data['clickLimit'],
      sponsorName: data['sponsorName'],
      sponsorInfo: data['sponsorInfo'],
      localization: (data['localization'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(
          key,
          BannerLocalization.fromMap(value as Map<String, dynamic>),
        ),
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'],
      impressionCount: data['impressionCount'] ?? 0,
      clickCount: data['clickCount'] ?? 0,
    );
  }

  /// Converts the campaign to a map for Firestore.
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'mainText': mainText,
      'subtitle': subtitle,
      'type': type.name,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'ctaLabel': ctaLabel,
      'destinationType': destinationType.name,
      'destinationValue': destinationValue,
      'placement': placement.name,
      'priority': priority,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'targetAudience': targetAudience.name,
      'deviceTargeting': deviceTargeting,
      'status': status.name,
      'impressionLimit': impressionLimit,
      'clickLimit': clickLimit,
      'sponsorName': sponsorName,
      'sponsorInfo': sponsorInfo,
      'localization': localization?.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'impressionCount': impressionCount,
      'clickCount': clickCount,
    };
  }

  /// Creates a copy with updated fields.
  BannerCampaign copyWith({
    String? title,
    String? mainText,
    String? subtitle,
    BannerType? type,
    String? imageUrl,
    String? videoUrl,
    String? ctaLabel,
    BannerDestinationType? destinationType,
    String? destinationValue,
    BannerPlacement? placement,
    int? priority,
    DateTime? startDate,
    DateTime? endDate,
    BannerAudience? targetAudience,
    List<String>? deviceTargeting,
    BannerStatus? status,
    int? impressionLimit,
    int? clickLimit,
    String? sponsorName,
    String? sponsorInfo,
    Map<String, BannerLocalization>? localization,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    int? impressionCount,
    int? clickCount,
  }) {
    return BannerCampaign(
      id: id,
      title: title ?? this.title,
      mainText: mainText ?? this.mainText,
      subtitle: subtitle ?? this.subtitle,
      type: type ?? this.type,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      ctaLabel: ctaLabel ?? this.ctaLabel,
      destinationType: destinationType ?? this.destinationType,
      destinationValue: destinationValue ?? this.destinationValue,
      placement: placement ?? this.placement,
      priority: priority ?? this.priority,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      targetAudience: targetAudience ?? this.targetAudience,
      deviceTargeting: deviceTargeting ?? this.deviceTargeting,
      status: status ?? this.status,
      impressionLimit: impressionLimit ?? this.impressionLimit,
      clickLimit: clickLimit ?? this.clickLimit,
      sponsorName: sponsorName ?? this.sponsorName,
      sponsorInfo: sponsorInfo ?? this.sponsorInfo,
      localization: localization ?? this.localization,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      impressionCount: impressionCount ?? this.impressionCount,
      clickCount: clickCount ?? this.clickCount,
    );
  }

  /// Checks if the banner is currently active based on schedule and status.
  bool isCurrentlyActive({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    return status == BannerStatus.active &&
        currentTime.isAfter(startDate) &&
        currentTime.isBefore(endDate);
  }

  /// Checks if the banner has reached its impression limit.
  bool hasReachedImpressionLimit() {
    if (impressionLimit == null) return false;
    return impressionCount >= impressionLimit!;
  }

  /// Checks if the banner has reached its click limit.
  bool hasReachedClickLimit() {
    if (clickLimit == null) return false;
    return clickCount >= clickLimit!;
  }

  /// Checks if the banner is eligible to display to a specific user.
  bool isEligibleForUser({
    required bool isSignedIn,
    required bool isSeller,
    required bool isBusinessAccount,
    required bool isKycApproved,
    required bool isBlueTick,
    String? deviceType,
  }) {
    if (!isCurrentlyActive()) return false;
    if (hasReachedImpressionLimit()) return false;
    if (hasReachedClickLimit()) return false;

    // Device targeting
    if (deviceTargeting != null && deviceTargeting!.isNotEmpty) {
      if (deviceType != null && !deviceTargeting!.contains(deviceType)) {
        return false;
      }
    }

    // Audience targeting
    switch (targetAudience) {
      case BannerAudience.allUsers:
        return true;
      case BannerAudience.signedInUsers:
        return isSignedIn;
      case BannerAudience.buyersOnly:
        return isSignedIn && !isSeller;
      case BannerAudience.sellersOnly:
        return isSignedIn && isSeller;
      case BannerAudience.businessAccounts:
        return isSignedIn && isBusinessAccount;
      case BannerAudience.kycApproved:
        return isSignedIn && isKycApproved;
      case BannerAudience.blueTickSellers:
        return isSignedIn && isBlueTick;
      case BannerAudience.nonBlueTickSellers:
        return isSignedIn && isSeller && !isBlueTick;
    }
  }
}

/// Localization data for a banner.
class BannerLocalization {
  BannerLocalization({
    required this.title,
    required this.mainText,
    this.subtitle,
    this.ctaLabel,
  });

  final String title;
  final String mainText;
  final String? subtitle;
  final String? ctaLabel;

  factory BannerLocalization.fromMap(Map<String, dynamic> map) {
    return BannerLocalization(
      title: map['title'] ?? '',
      mainText: map['mainText'] ?? '',
      subtitle: map['subtitle'],
      ctaLabel: map['ctaLabel'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'mainText': mainText,
      'subtitle': subtitle,
      'ctaLabel': ctaLabel,
    };
  }
}

/// Banner impression event for analytics.
class BannerImpressionEvent {
  BannerImpressionEvent({
    required this.bannerId,
    required this.userId,
    required this.placement,
    required this.timestamp,
    this.deviceType,
    this.appVersion,
  });

  final String bannerId;
  final String userId;
  final BannerPlacement placement;
  final DateTime timestamp;
  final String? deviceType;
  final String? appVersion;

  Map<String, dynamic> toFirestore() {
    return {
      'bannerId': bannerId,
      'userId': userId,
      'placement': placement.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'deviceType': deviceType,
      'appVersion': appVersion,
    };
  }
}

/// Banner click event for analytics.
class BannerClickEvent {
  BannerClickEvent({
    required this.bannerId,
    required this.userId,
    required this.placement,
    required this.timestamp,
    this.deviceType,
    this.appVersion,
  });

  final String bannerId;
  final String userId;
  final BannerPlacement placement;
  final DateTime timestamp;
  final String? deviceType;
  final String? appVersion;

  Map<String, dynamic> toFirestore() {
    return {
      'bannerId': bannerId,
      'userId': userId,
      'placement': placement.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'deviceType': deviceType,
      'appVersion': appVersion,
    };
  }
}