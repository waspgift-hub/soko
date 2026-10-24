import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'banner_campaign.dart';
import '../api/api_client.dart';
import '../auth/auth_service.dart';
import '../cache/cache_manager.dart';
import '../secure_storage/secure_storage_service.dart';

/// Banner eligibility result with detailed context.
@immutable
class BannerEligibilityResult {
  const BannerEligibilityResult({
    required this.eligible,
    this.campaign,
    this.reason,
    this.dismissedUntil,
  });

  final bool eligible;
  final BannerCampaign? campaign;
  final String? reason;
  final DateTime? dismissedUntil;

  bool get shouldShow => eligible && campaign != null && campaign.status == CampaignStatus.active;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BannerEligibilityResult &&
          runtimeType == other.runtimeType &&
          eligible == other.eligible &&
          campaign == other.campaign &&
          reason == other.reason &&
          dismissedUntil == other.dismissedUntil;

  @override
  int get hashCode =>
      eligible.hashCode ^
      campaign.hashCode ^
      reason.hashCode ^
      dismissedUntil.hashCode;

  @override
  String toString() =>
      'BannerEligibilityResult(eligible: $eligible, campaign: ${campaign?.id}, reason: $reason, dismissedUntil: $dismissedUntil)';
}

/// Dismissal record for a banner.
@immutable
class BannerDismissal {
  const BannerDismissal({
    required this.campaignId,
    required this.dismissedAt,
    this.expiresAt,
    this.dismissalType = DismissalType.user,
  });

  final String campaignId;
  final DateTime dismissedAt;
  final DateTime? expiresAt;
  final DismissalType dismissalType;

  factory BannerDismissal.fromJson(Map<String, dynamic> json) {
    return BannerDismissal(
      campaignId: json['campaignId'] as String,
      dismissedAt: DateTime.parse(json['dismissedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      dismissalType: DismissalType.values.firstWhere(
        (e) => e.name == json['dismissalType'],
        orElse: () => DismissalType.user,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'campaignId': campaignId,
        'dismissedAt': dismissedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'dismissalType': dismissalType.name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BannerDismissal &&
          runtimeType == other.runtimeType &&
          campaignId == other.campaignId &&
          dismissedAt == other.dismissedAt &&
          expiresAt == other.expiresAt &&
          dismissalType == other.dismissalType;

  @override
  int get hashCode =>
      campaignId.hashCode ^
      dismissedAt.hashCode ^
      expiresAt.hashCode ^
      dismissalType.hashCode;
}

enum DismissalType {
  user,
  system,
  expired,
}

/// In-memory cache entry for banners.
class _BannerCacheEntry {
  const BannerCacheEntry({
    required this.campaigns,
    required this.fetchedAt,
    this.expiresAt,
  });

  final List<BannerCampaign> campaigns;
  final DateTime fetchedAt;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// Query parameters for fetching banners.
@immutable
class BannerFetchQuery {
  const BannerFetchQuery({
    this.placements,
    this.userId,
    this.userRoles,
    this.deviceType,
    this.locale,
    this.platform,
    this.country,
    this.forceRefresh = false,
  });

  final List<BannerPlacement>? placements;
  final String? userId;
  final List<String>? userRoles;
  final String? deviceType;
  final String? locale;
  final String? platform;
  final String? country;
  final bool forceRefresh;

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (placements != null) {
      params['placements'] = placements!.map((e) => e.name).join(',');
    }
    if (userId != null) params['userId'] = userId;
    if (userRoles != null) params['userRoles'] = userRoles!.join(',');
    if (deviceType != null) params['deviceType'] = deviceType;
    if (locale != null) params['locale'] = locale;
    if (platform != null) params['platform'] = platform;
    if (country != null) params['country'] = country;
    if (forceRefresh) params['forceRefresh'] = 'true';
    return params;
  }
}

/// Result of a banner fetch operation.
@immutable
class BannerFetchResult {
  const BannerFetchResult({
    required this.campaigns,
    this.fromCache = false,
    this.nextCursor,
    this.totalCount,
    this.fetchedAt,
  });

  final List<BannerCampaign> campaigns;
  final bool fromCache;
  final String? nextCursor;
  final int? totalCount;
  final DateTime? fetchedAt;
}

/// Banner service for managing banner display, eligibility, and caching.
class BannerService extends ChangeNotifier {
  BannerService._();

  static final BannerService _instance = BannerService._();
  static BannerService get instance => _instance;

  static const String _cacheKey = 'banner_campaigns';
  static const String _dismissalsKey = 'banner_dismissals';
  static const Duration _defaultCacheTtl = Duration(minutes: 30);
  static const Duration _dismissalExpiry = Duration(days: 30);

  final Dio _dio;
  final SecureStorageService _secureStorage;
  final CacheManager _cacheManager;
  final AuthService _authService;

  final _campaignsController = StreamController<List<BannerCampaign>>.broadcast();
  final _eligibilityController =
      StreamController<Map<String, BannerEligibilityResult>>.broadcast();

  // In-memory cache
  List<BannerCampaign>? _cachedCampaigns;
  DateTime? _cachedAt;
  Duration _cacheTtl = const Duration(minutes: 15);

  // Dismissal tracking
  Map<String, BannerDismissal> _dismissals = {};
  DateTime? _dismissalsLoadedAt;

  // Placement priorities for ordering
  static const Map<BannerPlacement, int> _placementPriority = {
    BannerPlacement.home: 100,
    BannerPlacement.category: 90,
    BannerPlacement.productDiscovery: 85,
    BannerPlacement.searchResults: 80,
    BannerPlacement.sellerDashboard: 70,
    BannerPlacement.eligibleAccountDashboard: 70,
    BannerPlacement.searchResults: 80,
  };

  BannerService._()
      : _dio = Dio(),
        _secureStorage = SecureStorageService(),
        _cacheManager = CacheManager(),
        _authService = AuthService() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadDismissals();
    await _warmCache();
  }

  // Stream getters
  Stream<List<BannerCampaign>> get campaignsStream => _campaignsController.stream;
  Stream<Map<String, BannerEligibilityResult>> get eligibilityStream =>
      _eligibilityController.stream;

  // Public getters
  List<BannerCampaign> get cachedCampaigns =>
      _cachedCampaigns ?? const [];
  bool get hasCachedData => _cachedCampaigns != null && _cachedAt != null;
  Duration get cacheTtl => _cacheTtl;
  set cacheTtl(Duration value) => _cacheTtl = value;

  /// Fetches campaigns from the server.
  Future<BannerFetchResult> fetchCampaigns({
    BannerFetchQuery? query,
    bool forceRefresh = false,
  }) async {
    try {
      final queryParams = query?.toQueryParams() ?? {};
      final response = await _dio.get(
        '/api/v1/banners',
        queryParameters: query?.toQueryParams(),
        options: Options(
          headers: await _getAuthHeaders(),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final campaigns = (data['banners'] as List)
          .map((e) => BannerCampaign.fromJson(e as Map<String, dynamic>))
          .toList();

      final result = BannerFetchResult(
        campaigns: campaigns,
        fromCache: false,
        nextCursor: data['nextCursor'] as String?,
        totalCount: data['totalCount'] as int?,
        fetchedAt: DateTime.now(),
      );

      // Update cache
      _cachedCampaigns = campaigns;
      _cachedAt = DateTime.now();
      _saveCache(campaigns);
      _campaignsController.add(campaigns);

      notifyListeners();
      return result;
    } on DioException catch (e) {
      // Try to serve from cache on network error
      final cached = await _loadCache();
      if (cached != null && cached.isNotEmpty) {
        return BannerFetchResult(
          campaigns: cached,
          fromCache: true,
          fetchedAt: DateTime.now(),
        );
      }
      rethrow;
    }
  }

  /// Checks if a campaign is eligible for the current user/context.
  Future<BannerEligibilityResult> checkEligibility(
    BannerCampaign campaign, {
    String? userId,
    List<String>? userRoles,
    String? deviceType,
    String? locale,
    String? platform,
    String? country,
  }) async {
    final campaignId = campaign.id ?? '';

    // Check if dismissed
    final dismissal = _dismissals[campaign.id ?? ''];
    if (dismissal != null) {
      if (dismissal.expiresAt != null &&
          DateTime.now().isBefore(dismissal.expiresAt!)) {
        return BannerEligibilityResult(
          eligible: false,
          reason: 'dismissed',
          dismissedUntil: dismissal.expiresAt,
        );
      }
    }

    // Check status
    if (campaign.status != CampaignStatus.active) {
      return BannerEligibilityResult(
        eligible: false,
        reason: 'campaign_not_active',
      );
    }

    // Check schedule
    final now = DateTime.now();
    if (campaign.schedule.startAt != null &&
        campaign.schedule.startAt!.isAfter(DateTime.now())) {
      return BannerEligibilityResult(
        eligible: false,
        reason: 'not_yet_started',
      );
    }

    if (campaign.schedule.endAt != null &&
        campaign.schedule.endAt!.isBefore(DateTime.now())) {
      return BannerEligibilityResult(
        eligible: false,
        reason: 'expired',
      );
    }

    // Check day/time restrictions
    if (campaign.schedule.daysOfWeek != null &&
        campaign.schedule.daysOfWeek!.isNotEmpty) {
      final now = DateTime.now();
      final weekday = _dayOfWeekString(now.weekday);
      if (!campaign.schedule.daysOfWeek!.contains(weekday)) {
        return BannerEligibilityResult(
          eligible: false,
          reason: 'not_scheduled_today',
        );
      }
    }

    if (campaign.schedule.startTime != null ||
        campaign.schedule.endTime != null) {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      if (campaign.schedule.startTime != null &&
          campaign.schedule.startTime!.compareTo(
                    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}') >
                0) {
        return BannerEligibilityResult(
          eligible: false,
          reason: 'not_yet_started_today',
        );
      }

      if (campaign.schedule.endTime != null &&
          campaign.schedule.endTime!.compareTo(
                    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}') <
                0) {
        return BannerEligibilityResult(
          eligible: false,
          reason: 'ended_for_today',
        );
      }
    }

    // Check audience eligibility
    if (campaign.audience != null) {
      final audience = campaign.audience!;

      // Check signed-in status
      if (audience.signedInOnly == true) {
        // This would need auth state - simplified for now
      }

      // Check blue tick requirement
      if (audience.blueTickOnly == true) {
        // Would need user's blue tick status
      }

      // Check account types
      if (audience.accountTypes != null && audience.accountTypes!.isNotEmpty) {
        // Would check user's account type
      }

      // Check platforms
      if (audience.platforms != null && audience.platforms!.isNotEmpty) {
        final platform = 'flutter'; // Simplified
        if (!audience.platforms!.contains('flutter') &&
            !audience.platforms!.contains('all')) {
          return BannerEligibilityResult(
            eligible: false,
            reason: 'platform_not_eligible',
          );
        }
      }

      // Check countries
      if (audience.countries != null && audience.countries!.isNotEmpty) {
        // Would check user's country
      }
    }

    // Check impression/click caps
    if (campaign.maxImpressions != null) {
      // Would check against metrics
    }

    if (campaign.maxClicks != null) {
      // Would check against metrics
    }

    return BannerEligibilityResult(
      eligible: true,
      campaign: campaign,
      reason: 'eligible',
    );
  }

  /// Gets eligible banners for a placement.
  Future<List<BannerCampaign>> getEligibleBanners({
    required BannerPlacement placement,
    String? userId,
    List<String>? userRoles,
    String? locale,
    String? platform,
    String? country,
    int limit = 10,
  }) async {
    final campaigns = await _getCachedOrFetchCampaigns();

    final eligible = <BannerCampaign>[];
    for (final campaign in _cachedCampaigns ?? []) {
      if (!campaign.placements.contains(placement)) continue;

      final eligibility = await _checkEligibilityCached(campaign);
      if (eligibility.eligible) {
        eligible.add(campaign);
      }
    }

    // Sort by priority
    eligible.sort((a, b) {
      final aPriority = _placementPriority[a.placements.first] ?? 0;
      final bPriority = _placementPriority[b.placements.first] ?? 0;
      if (bPriority != aPriority) return bPriority.compareTo(aPriority);
      return (b.priority ?? 0).compareTo(a.priority ?? 0);
    });

    return eligible.take(limit).toList();
  }

  /// Checks eligibility with caching.
  Future<BannerEligibilityResult> _checkEligibilityCached(BannerCampaign campaign) async {
    final key = campaign.id ?? '';
    // In a real implementation, this would cache results
    return checkEligibility(campaign);
  }

  /// Dismisses a banner for the current user.
  Future<void> dismissBanner(String campaignId, {Duration? expiresIn}) async {
    final dismissal = BannerDismissal(
      campaignId: campaignId,
      dismissedAt: DateTime.now(),
      expiresAt: expiresIn != null ? DateTime.now().add(expiresIn!) : null,
      dismissalType: DismissalType.user,
    );

    _dismissals[campaignId] = BannerDismissal(
      campaignId: campaignId,
      dismissedAt: DateTime.now(),
      expiresAt: dismissal.expiresAt ?? DateTime.now().add(const Duration(days: 30)),
    );

    await _saveDismissals();
    notifyListeners();
  }

  /// Undismisses a banner.
  Future<void> undismissBanner(String campaignId) async {
    _dismissals.remove(campaignId);
    await _saveDismissals();
    notifyListeners();
  }

  /// Checks if a campaign is dismissed.
  bool isDismissed(String campaignId) {
    final dismissal = _dismissals[campaignId];
    if (dismissal == null) return false;

    if (dismissal.expiresAt != null &&
        DateTime.now().isAfter(dismissal.expiresAt!)) {
      _dismissals.remove(campaignId);
      _saveDismissals();
      return false;
    }
    return true;
  }

  /// Gets the next banner to show for a placement.
  Future<BannerCampaign?> getNextBanner({
    required BannerPlacement placement,
    String? userId,
    List<String>? userRoles,
    String? locale,
  }) async {
    final campaigns = await getEligibleBanners(
      placement: placement,
      limit: 1,
    );
    return campaigns.isNotEmpty ? campaigns.first : null;
  }

  /// Records an impression.
  Future<void> recordImpression(String campaignId) async {
    // In a real implementation, this would send to analytics
    // For now, we just track locally
  }

  /// Records a click.
  Future<void> recordClick(String campaignId) async {
    // Track click for analytics
  }

  /// Gets all active campaigns for a placement.
  Future<List<BannerCampaign>> getCampaignsForPlacement(
    BannerPlacement placement, {
    int limit = 10,
  }) async {
    final campaigns = await _getCachedOrFetchCampaigns();
    return campaigns
        .where((c) => c.placements.contains(placement) &&
            c.status == CampaignStatus.active)
        .toList()
      ..sort((a, b) => (b.priority ?? 0).compareTo(a.priority ?? 0))
      ..take(10).toList();
  }

  // Private methods
  Future<void> _initialize() async {
    await _loadDismissals();
    await _warmCache();
  }

  Future<void> _warmCache() async {
    try {
      await fetchCampaigns();
    } catch (_) {
      // Ignore warmup failures
    }
  }

  Future<void> _loadDismissals() async {
    try {
      final data = await _secureStorage.read(key: 'banner_dismissals');
      if (data != null) {
        final dataList = (json.decode(data) as List).cast<Map<String, dynamic>>();
        _dismissals = {
          for (final item in dataList)
            BannerDismissal.fromJson(item).campaignId: BannerDismissal.fromJson(item)
        };
      }
    } catch (_) {
      _dismissals = {};
    }
  }

  Future<void> _saveDismissals() async {
    try {
      final data = _dismissals.values.map((d) => d.toJson()).toList();
      await SecureStorageService.write(
        key: 'banner_dismissals',
        value: jsonEncode(_dismissals.values.map((d) => d.toJson()).toList()),
      );
    } catch (_) {
      // Ignore save failures
    }
  }

  Future<void> _saveCache(List<BannerCampaign> campaigns) async {
    try {
      final data = campaigns.map((c) => c.toJson()).toList();
      await CacheManager().setJson('banner_campaigns', {
        'campaigns': campaigns.map((c) => c.toJson()).toList(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Ignore
    }
  }

  Future<List<BannerCampaign>?> _loadCache() async {
    try {
      final data = await CacheManager().getJson('banner_campaigns');
      if (data == null) return null;

      final campaigns = (data['campaigns'] as List)
          .map((e) => BannerCampaign.fromJson(e as Map<String, dynamic>))
          .toList();
      final timestamp = DateTime.parse(data['timestamp'] as String);
      if (DateTime.now().difference(data['fetchedAt'] as DateTime) >
          const Duration(hours: 1)) {
        return null; // Cache expired
      }
      return campaigns;
    } catch (_) {
      return null;
    }
  }

  Future<List<BannerCampaign>> _getCachedOrFetchCampaigns() async {
    if (_cachedCampaigns != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < Duration(minutes: 15)) {
      return _cachedCampaigns!;
    }
    final result = await fetchCampaigns();
    return result.campaigns;
  }

  Map<String, dynamic> _getAuthHeaders() {
    // Implementation would add auth headers
    return {};
  }

  Future<void> _loadDismissals() async {
    // Load from secure storage
  }

  @override
  void dispose() {
    _campaignsController.close();
    _eligibilityController.close();
    super.dispose();
  }
}