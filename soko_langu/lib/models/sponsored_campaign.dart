import 'package:cloud_firestore/cloud_firestore.dart';

class SponsoredCampaign {
  final String id;
  final String sellerId;
  final String name;
  final String? storeName;
  final BigInt dailyBudgetTzs;
  final BigInt totalBudgetTzs;
  final BigInt bidAmountTzs;
  final String status;
  final String placement;
  final DateTime startsAt;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int impressions;
  final int clicks;
  final BigInt spendTzs;
  final List<CampaignPlacement> placements;
  final CampaignPayment? payment;
  final List<CampaignAuditLog> auditLogs;

  SponsoredCampaign({
    required this.id,
    required this.sellerId,
    required this.name,
    this.storeName,
    required this.dailyBudgetTzs,
    required this.totalBudgetTzs,
    required this.bidAmountTzs,
    required this.status,
    this.placement = 'search',
    required this.startsAt,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
     this.impressions = 0,
    this.clicks = 0,
    BigInt? spendTzs,
    this.placements = const [],
    this.payment,
    this.auditLogs = const [],
  }) : spendTzs = spendTzs ?? BigInt.zero;

  bool get isActive => status == 'active' && DateTime.now().isBefore(expiresAt);

  bool get isDraft => status == 'draft';

  bool get isPaymentPending => status == 'payment_pending';

  bool get isPaused => status == 'paused';

  bool get isCompleted => status == 'completed';

  bool get isCancelled => status == 'cancelled';

  bool get isRejected => status == 'rejected';

  bool get isExpired => status == 'expired';

  bool get isOutOfBudget => status == 'out_of_budget';

  bool get isTerminal =>
      isCompleted || isCancelled || isRejected || isExpired;

  factory SponsoredCampaign.fromApi(Map<String, dynamic> json) {
    return SponsoredCampaign(
      id: json['id']?.toString() ?? '',
      sellerId: json['sellerId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      storeName: json['seller'] is Map<String, dynamic>
          ? (json['seller'] as Map<String, dynamic>)['storeName']?.toString()
          : null,
      dailyBudgetTzs: BigInt.from(json['dailyBudgetTzs'] ?? 0),
      totalBudgetTzs: BigInt.from(json['totalBudgetTzs'] ?? 0),
      bidAmountTzs: BigInt.from(json['bidAmountTzs'] ?? 0),
      status: json['status']?.toString() ?? 'draft',
      placement: json['placement']?.toString() ?? 'search',
      startsAt: _parseDate(json['startsAt']),
      expiresAt: _parseDate(json['expiresAt']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      impressions: (json['impressions'] as num?)?.toInt() ?? 0,
      clicks: (json['clicks'] as num?)?.toInt() ?? 0,
      spendTzs: BigInt.from(json['spendTzs'] ?? 0),
      placements: (json['placements'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((p) => CampaignPlacement.fromApi(p))
          .toList(),
      payment: json['payment'] is Map<String, dynamic>
          ? CampaignPayment.fromApi(json['payment'] as Map<String, dynamic>)
          : null,
      auditLogs: (json['auditLogs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((a) => CampaignAuditLog.fromApi(a))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'dailyBudgetTzs': dailyBudgetTzs.toString(),
    'totalBudgetTzs': totalBudgetTzs.toString(),
    'bidAmountTzs': bidAmountTzs.toString(),
    'placement': placement,
    'startsAt': startsAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'productIds': placements.map((p) => p.productId).toList(),
    'isAllProducts': placements.any((p) => p.isAllProducts),
  };
}

DateTime _parseDate(dynamic raw) {
  if (raw == null) return DateTime.now();
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
  if (raw is Map && raw['_seconds'] is num) {
    return DateTime.fromMillisecondsSinceEpoch(((raw['_seconds'] as num) * 1000).toInt()).toLocal();
  }
  return DateTime.now();
}

class CampaignPlacement {
  final String id;
  final String campaignId;
  final String? productId;
  final bool isAllProducts;
  final DateTime createdAt;

  CampaignPlacement({
    required this.id,
    required this.campaignId,
    this.productId,
    this.isAllProducts = false,
    required this.createdAt,
  });

  factory CampaignPlacement.fromApi(Map<String, dynamic> json) {
    return CampaignPlacement(
      id: json['id']?.toString() ?? '',
      campaignId: json['campaignId']?.toString() ?? '',
      productId: json['productId']?.toString(),
      isAllProducts: json['isAllProducts'] as bool? ?? false,
      createdAt: _parseDate(json['createdAt']),
    );
  }
}

class CampaignPayment {
  final String id;
  final String campaignId;
  final String provider;
  final String? providerOrderId;
  final BigInt amountTzs;
  final String currency;
  final String status;
  final DateTime? webhookReceivedAt;
  final DateTime? verifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  CampaignPayment({
    required this.id,
    required this.campaignId,
    required this.provider,
    this.providerOrderId,
    required this.amountTzs,
    this.currency = 'TZS',
    this.status = 'pending',
    this.webhookReceivedAt,
    this.verifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CampaignPayment.fromApi(Map<String, dynamic> json) {
    return CampaignPayment(
      id: json['id']?.toString() ?? '',
      campaignId: json['campaignId']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      providerOrderId: json['providerOrderId']?.toString(),
      amountTzs: BigInt.from(json['amountTzs'] ?? json['amount'] ?? 0),
      currency: json['currency']?.toString() ?? 'TZS',
      status: json['status']?.toString() ?? 'pending',
      webhookReceivedAt: _parseDate(json['webhookReceivedAt']),
      verifiedAt: _parseDate(json['verifiedAt']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }
}

class CampaignAuditLog {
  final String id;
  final String campaignId;
  final String? actorId;
  final String actorType;
  final String action;
  final Map<String, dynamic>? oldState;
  final Map<String, dynamic>? newState;
  final DateTime createdAt;

  CampaignAuditLog({
    required this.id,
    required this.campaignId,
    this.actorId,
    this.actorType = 'user',
    required this.action,
    this.oldState,
    this.newState,
    required this.createdAt,
  });

  factory CampaignAuditLog.fromApi(Map<String, dynamic> json) {
    return CampaignAuditLog(
      id: json['id']?.toString() ?? '',
      campaignId: json['campaignId']?.toString() ?? '',
      actorId: json['actorId']?.toString(),
      actorType: json['actorType']?.toString() ?? 'user',
      action: json['action']?.toString() ?? '',
      oldState: json['oldState'] as Map<String, dynamic>?,
      newState: json['newState'] as Map<String, dynamic>?,
      createdAt: _parseDate(json['createdAt']),
    );
  }
}

class SponsoredMetrics {
  final String campaignId;
  final String campaignName;
  final int impressions;
  final int clicks;
  final BigInt spendTzs;
  final double ctr;

  SponsoredMetrics({
    required this.campaignId,
    required this.campaignName,
    required this.impressions,
    required this.clicks,
    required this.spendTzs,
    required this.ctr,
  });

  factory SponsoredMetrics.fromApi(Map<String, dynamic> json) {
    final impr = (json['impressions'] as num?)?.toInt() ?? 0;
    final clk = (json['clicks'] as num?)?.toInt() ?? 0;
    return SponsoredMetrics(
      campaignId: json['campaignId']?.toString() ?? '',
      campaignName: json['campaignName']?.toString() ?? '',
      impressions: impr,
      clicks: clk,
      spendTzs: BigInt.from(json['spendTzs'] ?? 0),
      ctr: impr > 0 ? clk / impr : 0.0,
    );
  }
}

class BudgetTier {
  final String key;
  final String name;
  final int dailyBudget;
  final int durationDays;
  final String color;

  BudgetTier({
    required this.key,
    required this.name,
    required this.dailyBudget,
    required this.durationDays,
    required this.color,
  });

  factory BudgetTier.fromJson(Map<String, dynamic> json) {
    return BudgetTier(
      key: json['key']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      dailyBudget: (json['dailyBudget'] as num?)?.toInt() ?? 0,
      durationDays: (json['durationDays'] as num?)?.toInt() ?? 0,
      color: json['color']?.toString() ?? '#6B7280',
    );
  }
}

/// Platform-wide sponsored metrics shown on the admin panel.
class AdminSponsoredSummary {
  final int totalCampaigns;
  final int activeCampaigns;
  final int pendingCampaigns;
  final int rejectedCampaigns;
  final int totalImpressions;
  final int totalClicks;
  final BigInt totalSpendTzs;
  final BigInt totalRevenueTzs;
  final double ctr;

  AdminSponsoredSummary({
    this.totalCampaigns = 0,
    this.activeCampaigns = 0,
    this.pendingCampaigns = 0,
    this.rejectedCampaigns = 0,
    this.totalImpressions = 0,
    this.totalClicks = 0,
    BigInt? totalSpendTzs,
    BigInt? totalRevenueTzs,
    this.ctr = 0,
  })  : totalSpendTzs = totalSpendTzs ?? BigInt.zero,
        totalRevenueTzs = totalRevenueTzs ?? BigInt.zero;

  factory AdminSponsoredSummary.fromApi(Map<String, dynamic> json) {
    final summary = json['summary'] is Map<String, dynamic>
        ? json['summary'] as Map<String, dynamic>
        : <String, dynamic>{};
    return AdminSponsoredSummary(
      totalCampaigns: (summary['totalCampaigns'] as num?)?.toInt() ?? 0,
      activeCampaigns: (summary['activeCampaigns'] as num?)?.toInt() ?? 0,
      pendingCampaigns: (summary['pendingCampaigns'] as num?)?.toInt() ?? 0,
      rejectedCampaigns: (summary['rejectedCampaigns'] as num?)?.toInt() ?? 0,
      totalImpressions: (summary['totalImpressions'] as num?)?.toInt() ?? 0,
      totalClicks: (summary['totalClicks'] as num?)?.toInt() ?? 0,
      totalSpendTzs: BigInt.from(summary['totalSpendTzs'] ?? 0),
      totalRevenueTzs: BigInt.from(summary['totalRevenueTzs'] ?? 0),
      ctr: (summary['ctr'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Admin-configured budget/duration limits for new campaigns.
class SponsoredLimits {
  final int minBudgetTzs;
  final int maxBudgetTzs;
  final int minDurationDays;
  final int maxDurationDays;

  SponsoredLimits({
    this.minBudgetTzs = 1000,
    this.maxBudgetTzs = 10000000,
    this.minDurationDays = 1,
    this.maxDurationDays = 90,
  });

  factory SponsoredLimits.fromApi(Map<String, dynamic> json) {
    return SponsoredLimits(
      minBudgetTzs: (json['minBudgetTzs'] as num?)?.toInt() ?? 1000,
      maxBudgetTzs: (json['maxBudgetTzs'] as num?)?.toInt() ?? 10000000,
      minDurationDays: (json['minDurationDays'] as num?)?.toInt() ?? 1,
      maxDurationDays: (json['maxDurationDays'] as num?)?.toInt() ?? 90,
    );
  }
}

