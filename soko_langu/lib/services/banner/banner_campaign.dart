import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'banner_campaign.freezed.dart';
part 'banner_campaign.g.dart';

/// Supported banner types as defined in the requirements.
enum BannerType {
  @JsonValue('SPONSORED_AD')
  sponsoredAd,
  @JsonValue('PROMOTION')
  promotion,
  @JsonValue('NEW_FEATURE')
  newFeature,
  @JsonValue('PLATFORM_ANNOUNCEMENT')
  platformAnnouncement,
  @JsonValue('ADMIN_CONFIGURED_BANNER')
  adminConfiguredBanner,
}

/// Banner campaign status.
enum CampaignStatus {
  @JsonValue('DRAFT')
  draft,
  @JsonValue('SCHEDULED')
  scheduled,
  @JsonValue('ACTIVE')
  active,
  @JsonValue('PAUSED')
  paused,
  @JsonValue('EXPIRED')
  expired,
  @JsonValue('ARCHIVED')
  archived,
}

/// Where the banner can be displayed.
enum BannerPlacement {
  @JsonValue('HOME')
  home,
  @JsonValue('CATEGORY')
  category,
  @JsonValue('PRODUCT_DISCOVERY')
  productDiscovery,
  @JsonValue('SEARCH_RESULTS')
  searchResults,
  @JsonValue('SELLER_DASHBOARD')
  sellerDashboard,
  @JsonValue('ELIGIBLE_ACCOUNT_DASHBOARD')
  eligibleAccountDashboard,
  @JsonValue('SEARCH_RESULTS')
  searchResults,
}

/// Banner visual variant.
enum BannerVisualVariant {
  @JsonValue('COMPACT')
  compact,
  @JsonValue('FULL_WIDTH')
  fullWidth,
  @JsonValue('SPONSORED_PRODUCT')
  sponsoredProduct,
  @JsonValue('FEATURE_ANNOUNCEMENT')
  featureAnnouncement,
  @JsonValue('INFORMATIONAL')
  informational,
}

/// Where the banner should navigate when tapped.
enum BannerDestinationType {
  @JsonValue('ROUTE')
  route,
  @JsonValue('EXTERNAL_URL')
  externalUrl,
  @JsonValue('DEEP_LINK')
  deepLink,
  @JsonValue('NONE')
  none,
}

/// Audience targeting rules.
@freezed
class BannerAudienceRule with _$BannerAudienceRule {
  const factory BannerAudienceRule({
    /// Target signed-in users vs visitors
    @JsonKey(includeIfNull: false) bool? signedInOnly,
    @JsonKey(includeIfNull: false) bool? guestsOnly,

    /// Target specific account types
    @JsonKey(includeIfNull: false) List<String>? accountTypes,

    /// Target specific user roles
    @JsonKey(includeIfNull: false) List<String>? roles,

    /// Target blue tick sellers
    @JsonKey(includeIfNull: false) bool? blueTickOnly,

    /// Minimum account age in days
    @JsonKey(includeIfNull: false) int? minAccountAgeDays,

    /// Minimum number of transactions
    @JsonKey(includeIfNull: false) int? minTransactions,

    /// Platform targeting
    @JsonKey(includeIfNull: false) List<String>? platforms,

    /// Country/region targeting
    @JsonKey(includeIfNull: false) List<String>? countries,

    /// Custom segment IDs
    @JsonKey(includeIfNull: false) List<String>? segmentIds,
  }) = _BannerAudienceRule;

  factory BannerAudienceRule.fromJson(Map<String, dynamic> json) =>
      _$BannerAudienceRuleFromJson(json);
}

/// Banner destination configuration.
@freezed
class BannerDestination with _$BannerDestination {
  const factory BannerDestination({
    @JsonKey(includeIfNull: false) BannerDestinationType? type,
    @JsonKey(includeIfNull: false) String? route,
    @JsonKey(includeIfNull: false) String? externalUrl,
    @JsonKey(includeIfNull: false) String? deepLink,
    @JsonKey(includeIfNull: false) Map<String, dynamic>? parameters,
  }) = _BannerDestination;

  factory BannerDestination.fromJson(Map<String, dynamic> json) =>
      _$BannerDestinationFromJson(json);
}

/// Banner asset (image/video).
@freezed
class BannerAsset with _$BannerAsset {
  const factory BannerAsset({
    @JsonKey(includeIfNull: false) String? id,
    @JsonKey(includeIfNull: false) required String url,
    @JsonKey(includeIfNull: false) String? altText,
    @JsonKey(includeIfNull: false) int? width,
    @JsonKey(includeIfNull: false) int? height,
    @JsonKey(includeIfNull: false) int? fileSize,
    @JsonKey(includeIfNull: false) String? mimeType,
    @JsonKey(includeIfNull: false) Duration? duration,
    @JsonKey(includeIfNull: false) String? thumbnailUrl,
  }) = _BannerAsset;

  factory BannerAsset.fromJson(Map<String, dynamic> json) =>
      _$BannerAssetFromJson(json);
}

/// Banner schedule configuration.
@freezed
class BannerSchedule with _$BannerSchedule {
  const factory BannerSchedule({
    @JsonKey(includeIfNull: false) DateTime? startAt,
    @JsonKey(includeIfNull: false) DateTime? endAt,
    @JsonKey(includeIfNull: false) List<String>? daysOfWeek, // e.g., ['mon', 'tue', 'wed']
    @JsonKey(includeIfNull: false) String? startTime, // HH:MM format
    @JsonKey(includeIfNull: false) String? endTime, // HH:MM format
    @JsonKey(includeIfNull: false) String? timeZone, // IANA timezone
  }) = _BannerSchedule;

  factory BannerSchedule.fromJson(Map<String, dynamic> json) =>
      _$BannerScheduleFromJson(json);
}

/// Campaign performance metrics.
@freezed
class CampaignMetrics with _$CampaignMetrics {
  const factory CampaignMetrics({
    @JsonKey(includeIfNull: false) int? impressions,
    @JsonKey(includeIfNull: false) int? clicks,
    @JsonKey(includeIfNull: false) int? uniqueImpressions,
    @JsonKey(includeIfNull: false) double? clickThroughRate,
    @JsonKey(includeIfNull: false) int? conversions,
    @JsonKey(includeIfNull: false) double? conversionRate,
    @JsonKey(includeIfNull: false) DateTime? lastUpdated,
  }) = _CampaignMetrics;

  factory CampaignMetrics.fromJson(Map<String, dynamic> json) =>
      _$CampaignMetricsFromJson(json);
}

/// Main banner campaign model.
@freezed
class BannerCampaign with _$BannerCampaign {
  const factory BannerCampaign({
    @JsonKey(includeIfNull: false) String? id,
    @JsonKey(includeIfNull: false) required String title,
    @JsonKey(includeIfNull: false) String? subtitle,
    @JsonKey(includeIfNull: false) String? description,
    @JsonKey(includeIfNull: false) required BannerType type,
    @JsonKey(includeIfNull: false) required List<BannerPlacement> placements,
    @JsonKey(includeIfNull: false) required BannerVisualVariant visualVariant,
    @JsonKey(includeIfNull: false) required CampaignStatus status,
    @JsonKey(includeIfNull: false) required BannerSchedule schedule,
    @JsonKey(includeIfNull: false) BannerAudienceRule? audience,
    @JsonKey(includeIfNull: false) required BannerAsset asset,
    @JsonKey(includeIfNull: false) required BannerDestination destination,
    @JsonKey(includeIfNull: false) BannerVisualVariant? visualVariantOverride,
    @JsonKey(includeIfNull: false) int? priority,
    @JsonKey(includeIfNull: false) int? maxImpressions,
    @JsonKey(includeIfNull: false) int? maxClicks,
    @JsonKey(includeIfNull: false) int? frequencyCap,
    @JsonKey(includeIfNull: false) int? minDisplayIntervalSeconds,
    @JsonKey(includeIfNull: false) String? sponsorName,
    @JsonKey(includeIfNull: false) String? sponsorId,
    @JsonKey(includeIfNull: false) String? campaignReference,
    @JsonKey(includeIfNull: false) Map<String, String>? localizedContent,
    @JsonKey(includeIfNull: false) Map<String, String>? metadata,
    @JsonKey(includeIfNull: false) CampaignMetrics? metrics,
    @JsonKey(includeIfNull: false) DateTime? createdAt,
    @JsonKey(includeIfNull: false) DateTime? updatedAt,
    @JsonKey(includeIfNull: false) String? createdBy,
    @JsonKey(includeIfNull: false) String? updatedBy,
  }) = _BannerCampaign;

  factory BannerCampaign.fromJson(Map<String, dynamic> json) =>
      _$BannerCampaignFromJson(json);
}

/// Banner eligibility result.
@freezed
class BannerEligibility with _$BannerEligibility {
  const factory BannerEligibility({
    required bool eligible,
    @JsonKey(includeIfNull: false) String? reason,
    @JsonKey(includeIfNull: false) BannerCampaign? campaign,
  }) = _BannerEligibility;

  factory BannerEligibility.fromJson(Map<String, dynamic> json) =>
      _$BannerEligibilityFromJson(json);
}

/// Banner query parameters for client requests.
@freezed
class BannerQuery with _$BannerQuery {
  const factory BannerQuery({
    @JsonKey(includeIfNull: false) List<BannerPlacement>? placements,
    @JsonKey(includeIfNull: false) String? userId,
    @JsonKey(includeIfNull: false) List<String>? userRoles,
    @JsonKey(includeIfNull: false) String? deviceType,
    @JsonKey(includeIfNull: false) String? locale,
    @JsonKey(includeIfNull: false) String? platform,
    @JsonKey(includeIfNull: false) String? country,
  }) = _BannerQuery;

  factory BannerQuery.fromJson(Map<String, dynamic> json) =>
      _$BannerQueryFromJson(json);
}

/// Banner response from the server.
@freezed
class BannerResponse with _$BannerResponse {
  const factory BannerResponse({
    required List<BannerCampaign> banners,
    @JsonKey(includeIfNull: false) String? nextCursor,
    @JsonKey(includeIfNull: false) int? totalCount,
  }) = _BannerResponse;

  factory BannerResponse.fromJson(Map<String, dynamic> json) =>
      _$BannerResponseFromJson(json);
}

/// Admin banner list query parameters.
@freezed
class AdminBannerQuery with _$AdminBannerQuery {
  const factory AdminBannerQuery({
    @JsonKey(includeIfNull: false) String? search,
    @JsonKey(includeIfNull: false) List<CampaignStatus>? status,
    @JsonKey(includeIfNull: false) List<BannerType>? type,
    @JsonKey(includeIfNull: false) List<BannerPlacement>? placement,
    @JsonKey(includeIfNull: false) String? sponsorId,
    @JsonKey(includeIfNull: false) DateTime? startDate,
    @JsonKey(includeIfNull: false) DateTime? endDate,
    @JsonKey(includeIfNull: false) int? page,
    @JsonKey(includeIfNull: false) int? limit,
    @JsonKey(includeIfNull: false) String? sortBy,
    @JsonKey(includeIfNull: false) bool? sortDesc,
  }) = _AdminBannerQuery;

  factory AdminBannerQuery.fromJson(Map<String, dynamic> json) =>
      _$AdminBannerQueryFromJson(json);
}

/// Admin banner list response.
@freezed
class AdminBannerListResponse with _$AdminBannerListResponse {
  const factory AdminBannerListResponse({
    required List<BannerCampaign> banners,
    @JsonKey(includeIfNull: false) int? totalCount,
    @JsonKey(includeIfNull: false) int? page,
    @JsonKey(includeIfNull: false) int? limit,
    @JsonKey(includeIfNull: false) int? totalPages,
  }) = _AdminBannerListResponse;

  factory AdminBannerListResponse.fromJson(Map<String, dynamic> json) =>
      _$AdminBannerListResponseFromJson(json);
}

/// Banner preview request.
@freezed
class BannerPreviewRequest with _$BannerPreviewRequest {
  const factory BannerPreviewRequest({
    @JsonKey(includeIfNull: false) required BannerCampaign campaign,
    @JsonKey(includeIfNull: false) String? deviceType,
    @JsonKey(includeIfNull: false) String? locale,
  }) = _BannerPreviewRequest;

  factory BannerPreviewRequest.fromJson(Map<String, dynamic> json) =>
      _$BannerPreviewRequestFromJson(json);
}

/// Banner preview response.
@freezed
class BannerPreviewResponse with _$BannerPreviewResponse {
  const factory BannerPreviewResponse({
    required String html,
    @JsonKey(includeIfNull: false) String? screenshotUrl,
  }) = _BannerPreviewResponse;

  factory BannerPreviewResponse.fromJson(Map<String, dynamic> json) =>
      _$BannerPreviewResponseFromJson(json);
}

/// Bulk action request for campaigns.
@freezed
class BulkCampaignAction with _$BulkCampaignAction {
  const factory BulkCampaignAction({
    required List<String> campaignIds,
    required String action, // 'publish', 'pause', 'resume', 'archive', 'duplicate'
    @JsonKey(includeIfNull: false) Map<String, dynamic>? parameters,
  }) = _BulkCampaignAction;

  factory BulkCampaignAction.fromJson(Map<String, dynamic> json) =>
      _$BulkCampaignActionFromJson(json);
}