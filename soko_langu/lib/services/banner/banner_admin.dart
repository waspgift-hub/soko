import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'banner_admin.freezed.dart';
part 'banner_admin.g.dart';

/// Admin banner creation/update request.
@freezed
class AdminBannerRequest with _$AdminBannerRequest {
  const factory AdminBannerRequest({
    @JsonKey(includeIfNull: false) String? id,
    @JsonKey(includeIfNull: false) required String title,
    @JsonKey(includeIfNull: false) String? subtitle,
    @JsonKey(includeIfNull: false) String? description,
    @JsonKey(includeIfNull: false) required String type,
    @JsonKey(includeIfNull: false) required List<String> placements,
    @JsonKey(includeIfNull: false) required String visualVariant,
    @JsonKey(includeIfNull: false) required String status,
    @JsonKey(includeIfNull: false) required Map<String, dynamic> schedule,
    @JsonKey(includeIfNull: false) Map<String, dynamic>? audience,
    @JsonKey(includeIfNull: false) required Map<String, dynamic> asset,
    @JsonKey(includeIfNull: false) required Map<String, dynamic> destination,
    @JsonKey(includeIfNull: false) String? visualVariantOverride,
    @JsonKey(includeIfNull: false) int? priority,
    @JsonKey(includeIfNull: false) int? maxImpressions,
    @JsonKey(includeIfNull: false) int? maxClicks,
    @JsonKey(includeIfNull: false) int? frequencyCap,
    @JsonKey(includeIfNull: false) int? minDisplayIntervalSeconds,
    @JsonKey(includeIfNull: false) String? sponsorName,
    @JsonKey(includeIfNull: false) String? sponsorId,
    @JsonKey(includeIfNull: false) String? campaignReference,
    @JsonKey(includeIfNull: false) Map<String, String>? localizedContent,
    @JsonKey(includeIfNull: false) Map<String, dynamic>? metadata,
  }) = _AdminBannerRequest;

  factory AdminBannerRequest.fromJson(Map<String, dynamic> json) =>
      _$AdminBannerRequestFromJson(json);
}

/// Admin banner list query.
@freezed
class AdminBannerQuery with _$AdminBannerQuery {
  const factory AdminBannerQuery({
    @JsonKey(includeIfNull: false) String? search,
    @JsonKey(includeIfNull: false) List<String>? status,
    @JsonKey(includeIfNull: false) List<String>? type,
    @JsonKey(includeIfNull: false) List<String>? placement,
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
    required List<Map<String, dynamic>> banners,
    @JsonKey(includeIfNull: false) int? totalCount,
    @JsonKey(includeIfNull: false) int? page,
    @JsonKey(includeIfNull: false) int? limit,
    @JsonKey(includeIfNull: false) int? totalPages,
  }) = _AdminBannerListResponse;

  factory AdminBannerListResponse.fromJson(Map<String, dynamic> json) =>
      _$AdminBannerListResponseFromJson(json);
}

/// Admin banner detail response.
@freezed
class AdminBannerDetail with _$AdminBannerDetail {
  const factory AdminBannerDetail({
    required Map<String, dynamic> banner,
    @JsonKey(includeIfNull: false) List<String>? eligiblePlacements,
    @JsonKey(includeIfNull: false) List<Map<String, dynamic>>? auditLog,
  }) = _AdminBannerDetail;

  factory AdminBannerDetail.fromJson(Map<String, dynamic> json) =>
      _$AdminBannerDetailFromJson(json);
}

/// Banner preview request.
@freezed
class BannerPreviewRequest with _$BannerPreviewRequest {
  const factory BannerPreviewRequest({
    @JsonKey(includeIfNull: false) required Map<String, dynamic> campaign,
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

/// Bulk action on campaigns.
@freezed
class BulkCampaignAction with _$BulkCampaignAction {
  const factory BulkCampaignAction({
    required List<String> campaignIds,
    required String action, // publish, pause, resume, archive, duplicate
    @JsonKey(includeIfNull: false) Map<String, dynamic>? parameters,
  }) = _BulkCampaignAction;

  factory BulkCampaignAction.fromJson(Map<String, dynamic> json) =>
      _$BulkCampaignActionFromJson(json);
}

/// Campaign metrics response.
@freezed
class CampaignMetricsResponse with _$CampaignMetricsResponse {
  const factory CampaignMetricsResponse({
    required String campaignId,
    required int impressions,
    required int clicks,
    required double ctr,
    required int conversions,
    double? conversionRate,
    required Map<String, dynamic> byPlacement,
    required Map<String, dynamic> byDate,
    DateTime? lastUpdated,
  }) = _CampaignMetricsResponse;

  factory CampaignMetricsResponse.fromJson(Map<String, dynamic> json) =>
      _$CampaignMetricsResponseFromJson(json);
}