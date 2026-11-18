
/// A buyer's "Natafuta Bidhaa" request.
///
/// Field names mirror the server serialization in
/// `server/src/modules/buyer-requests/request-store.js` so the model stays a
/// thin, lossless mapping of the API contract.
class BuyerRequest {
  const BuyerRequest({
    required this.id,
    required this.buyerUid,
    this.buyerName = '',
    this.buyerAvatarUrl = '',
    this.buyerKycApproved = false,
    required this.title,
    this.description = '',
    this.categoryId = '',
    this.categoryName = '',
    this.images = const [],
    this.brand = '',
    this.model = '',
    this.condition = 'any',
    this.minBudget = 0,
    this.maxBudget = 0,
    this.location = '',
    this.delivery = 'negotiable',
    this.deliveryDetails = '',
    this.requirements = '',
    this.preferredContact = 'in_app',
    this.status = 'active',
    this.isExpiringSoon = false,
    this.timeRemainingMs = 0,
    this.offersCount = 0,
    this.totalOfferCount = 0,
    this.viewCount = 0,
    this.offerLimit = 10,
    this.editsUsed = 0,
    this.maxEdits = 5,
    this.version = 1,
    this.extensionsUsed = 0,
    this.canEdit = false,
    this.canExtend = false,
    this.canReopen = false,
    this.canClose = false,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.completedAt,
    this.isOwner = false,
    this.hasOffered = false,
    this.myOfferId,
    this.canOffer = false,
    this.offerBlockReason,
    this.moderation,
    this.serverTime,
  });

  final String id;
  final String buyerUid;
  final String buyerName;
  final String buyerAvatarUrl;
  final bool buyerKycApproved;
  final String title;
  final String description;
  final String categoryId;
  final String categoryName;
  final List<String> images;
  final String brand;
  final String model;
  final String condition;
  final int minBudget;
  final int maxBudget;
  final String location;
  final String delivery;
  final String deliveryDetails;
  final String requirements;
  final String preferredContact;
  final String status;
  final bool isExpiringSoon;
  final int timeRemainingMs;
  final int offersCount;
  final int totalOfferCount;
  final int viewCount;
  final int offerLimit;
  final int editsUsed;
  final int maxEdits;
  final int version;
  final int extensionsUsed;
  final bool canEdit;
  final bool canExtend;
  final bool canReopen;
  final bool canClose;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;
  final DateTime? completedAt;
  final bool isOwner;
  final bool hasOffered;
  final String? myOfferId;
  final bool canOffer;
  final String? offerBlockReason;
  final Map<String, dynamic>? moderation;
  final DateTime? serverTime;

  bool get isActive => status == 'active';
  bool get isLimitReached => status == 'limit_reached';
  bool get isExpired => status == 'expired';
  bool get isCompleted => status == 'completed';
  bool get isClosed => status == 'closed';
  bool get isSuspended => status == 'suspended';
  bool get hasImage => images.isNotEmpty;

  String get primaryImage => images.isNotEmpty ? images.first : '';

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  factory BuyerRequest.fromJson(Map<String, dynamic> json) {
    final buyer = (json['buyer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final budget = (json['budget'] as Map?)?.cast<String, dynamic>() ?? const {};
    final moderation = (json['moderation'] as Map?)?.cast<String, dynamic>();
    final myOffer = (json['myOffer'] as Map?)?.cast<String, dynamic>();
    return BuyerRequest(
      id: (json['id'] ?? '').toString(),
      buyerUid: (json['buyerUid'] ?? buyer['uid'] ?? '').toString(),
      buyerName: (json['buyerName'] ?? buyer['displayName'] ?? '').toString(),
      buyerAvatarUrl: (json['buyerAvatarUrl'] ?? buyer['avatarUrl'] ?? '').toString(),
      buyerKycApproved: (json['buyerKycApproved'] ?? buyer['kycApproved']) == true,
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      categoryId: (json['categoryId'] ?? '').toString(),
      categoryName: (json['categoryName'] ?? '').toString(),
      images: (json['images'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      brand: (json['brand'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      condition: (json['condition'] ?? 'any').toString(),
      minBudget: (json['minBudget'] ?? budget['min'] ?? 0) is num
          ? (json['minBudget'] ?? budget['min'] ?? 0).toInt()
          : int.tryParse('${json['minBudget'] ?? budget['min'] ?? 0}') ?? 0,
      maxBudget: (json['maxBudget'] ?? budget['max'] ?? 0) is num
          ? (json['maxBudget'] ?? budget['max'] ?? 0).toInt()
          : int.tryParse('${json['maxBudget'] ?? budget['max'] ?? 0}') ?? 0,
      location: (json['location'] ?? '').toString(),
      delivery: (json['delivery'] ?? 'negotiable').toString(),
      deliveryDetails: (json['deliveryDetails'] ?? '').toString(),
      requirements: (json['requirements'] ?? '').toString(),
      preferredContact: (json['preferredContact'] ?? 'in_app').toString(),
      status: (json['status'] ?? 'active').toString(),
      isExpiringSoon: json['isExpiringSoon'] == true,
      timeRemainingMs: (json['timeRemainingMs'] as num?)?.toInt() ?? 0,
      offersCount: (json['offersCount'] as num?)?.toInt() ?? 0,
      totalOfferCount: (json['totalOfferCount'] as num?)?.toInt() ?? 0,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      offerLimit: (json['offerLimit'] as num?)?.toInt() ?? 10,
      editsUsed: (json['editsUsed'] as num?)?.toInt() ?? 0,
      maxEdits: (json['maxEdits'] as num?)?.toInt() ?? 5,
      version: (json['version'] as num?)?.toInt() ?? 1,
      extensionsUsed: (json['extensionsUsed'] as num?)?.toInt() ?? 0,
      canEdit: json['canEdit'] == true,
      canExtend: json['canExtend'] == true,
      canReopen: json['canReopen'] == true,
      canClose: json['canClose'] == true,
      expiresAt: _date(json['expiresAt']),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      closedAt: _date(json['closedAt']),
      completedAt: _date(json['completedAt']),
      isOwner: json['isOwner'] == true,
      hasOffered: json['hasOffered'] == true,
      myOfferId: myOffer?['id']?.toString(),
      canOffer: json['canOffer'] == true,
      offerBlockReason: json['offerBlockReason']?.toString(),
      moderation: moderation,
      serverTime: _date(json['serverTime']),
    );
  }

  BuyerRequest copyWith({
    String? status,
    int? offersCount,
    int? viewCount,
    bool? canEdit,
  }) {
    return BuyerRequest(
      id: id,
      buyerUid: buyerUid,
      buyerName: buyerName,
      buyerAvatarUrl: buyerAvatarUrl,
      buyerKycApproved: buyerKycApproved,
      title: title,
      description: description,
      categoryId: categoryId,
      categoryName: categoryName,
      images: images,
      brand: brand,
      model: model,
      condition: condition,
      minBudget: minBudget,
      maxBudget: maxBudget,
      location: location,
      delivery: delivery,
      deliveryDetails: deliveryDetails,
      requirements: requirements,
      preferredContact: preferredContact,
      status: status ?? this.status,
      isExpiringSoon: isExpiringSoon,
      timeRemainingMs: timeRemainingMs,
      offersCount: offersCount ?? this.offersCount,
      totalOfferCount: totalOfferCount,
      viewCount: viewCount ?? this.viewCount,
      offerLimit: offerLimit,
      editsUsed: editsUsed,
      maxEdits: maxEdits,
      version: version,
      extensionsUsed: extensionsUsed,
      canEdit: canEdit ?? this.canEdit,
      canExtend: canExtend,
      canReopen: canReopen,
      canClose: canClose,
      expiresAt: expiresAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      closedAt: closedAt,
      completedAt: completedAt,
      isOwner: isOwner,
      hasOffered: hasOffered,
      myOfferId: myOfferId,
      canOffer: canOffer,
      offerBlockReason: offerBlockReason,
      moderation: moderation,
      serverTime: serverTime,
    );
  }

  @override
  bool operator ==(Object other) => other is BuyerRequest && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BuyerRequestOffer {
  const BuyerRequestOffer({
    required this.id,
    required this.requestId,
    required this.sellerUid,
    this.sellerName = '',
    this.sellerAvatarUrl = '',
    this.sellerStoreName = '',
    this.sellerKycApproved = false,
    this.sellerWhatsappEnabled = false,
    required this.price,
    this.currency = 'TZS',
    this.message = '',
    this.deliveryDays,
    this.condition = '',
    this.brand = '',
    this.model = '',
    this.warranty = '',
    this.status = 'pending',
    this.version = 1,
    this.requestVersion = 1,
    this.isMine = false,
    this.createdAt,
    this.updatedAt,
    this.decidedAt,
    this.withdrawnAt,
  });

  final String id;
  final String requestId;
  final String sellerUid;
  final String sellerName;
  final String sellerAvatarUrl;
  final String sellerStoreName;
  final bool sellerKycApproved;
  final bool sellerWhatsappEnabled;
  final int price;
  final String currency;
  final String message;
  final int? deliveryDays;
  final String condition;
  final String brand;
  final String model;
  final String warranty;
  final String status;
  final int version;
  final int requestVersion;
  final bool isMine;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? decidedAt;
  final DateTime? withdrawnAt;

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  factory BuyerRequestOffer.fromJson(Map<String, dynamic> json) {
    final seller = (json['seller'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BuyerRequestOffer(
      id: (json['id'] ?? '').toString(),
      requestId: (json['requestId'] ?? '').toString(),
      sellerUid: (json['sellerUid'] ?? seller['uid'] ?? '').toString(),
      sellerName: (json['sellerName'] ?? seller['displayName'] ?? '').toString(),
      sellerAvatarUrl: (json['sellerAvatarUrl'] ?? seller['avatarUrl'] ?? '').toString(),
      sellerStoreName: (json['sellerStoreName'] ?? seller['storeName'] ?? '').toString(),
      sellerKycApproved: (json['sellerKycApproved'] ?? seller['kycApproved']) == true,
      sellerWhatsappEnabled: (json['sellerWhatsappEnabled'] ?? seller['whatsappEnabled']) == true,
      price: (json['price'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] ?? 'TZS').toString(),
      message: (json['message'] ?? '').toString(),
      deliveryDays: (json['deliveryDays'] as num?)?.toInt(),
      condition: (json['condition'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      warranty: (json['warranty'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      requestVersion: (json['requestVersion'] as num?)?.toInt() ?? 1,
      isMine: json['isMine'] == true,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      decidedAt: _date(json['decidedAt']),
      withdrawnAt: _date(json['withdrawnAt']),
    );
  }
}

class BuyerRequestView {
  const BuyerRequestView({
    required this.sellerUid,
    this.sellerName = '',
    this.sellerAvatarUrl = '',
    this.sellerStoreName = '',
    this.sellerKycApproved = false,
    this.firstViewedAt,
    this.lastViewedAt,
    this.viewCount = 1,
  });

  final String sellerUid;
  final String sellerName;
  final String sellerAvatarUrl;
  final String sellerStoreName;
  final bool sellerKycApproved;
  final DateTime? firstViewedAt;
  final DateTime? lastViewedAt;
  final int viewCount;

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  factory BuyerRequestView.fromJson(Map<String, dynamic> json) {
    final seller = (json['seller'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BuyerRequestView(
      sellerUid: (json['sellerUid'] ?? seller['uid'] ?? '').toString(),
      sellerName: (json['sellerName'] ?? seller['displayName'] ?? '').toString(),
      sellerAvatarUrl: (json['sellerAvatarUrl'] ?? seller['avatarUrl'] ?? '').toString(),
      sellerStoreName: (json['sellerStoreName'] ?? seller['storeName'] ?? '').toString(),
      sellerKycApproved: (json['sellerKycApproved'] ?? seller['kycApproved']) == true,
      firstViewedAt: _date(json['firstViewedAt']),
      lastViewedAt: _date(json['lastViewedAt']),
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 1,
    );
  }
}
