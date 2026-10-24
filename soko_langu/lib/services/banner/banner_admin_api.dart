import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'banner_admin.dart';

/// Admin API service for banner management.
class BannerAdminApi {
  BannerAdminApi._();

  static final BannerAdminApi _instance = BannerAdminApi._();
  static BannerAdminApi get instance => _instance;

  BannerAdminApi._() : _dio = Dio();

  final Dio _dio;

  /// Gets the admin authorization headers.
  Future<Map<String, String>> _getAuthHeaders() async {
    // This would get the admin auth token
    // For now, return empty headers
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  /// Lists banners with filtering and pagination.
  Future<AdminBannerListResponse> listBanners({
    AdminBannerQuery? query,
  }) async {
    try {
      final queryParams = query?.toJson() ?? {};
      final response = await _dio.get(
        '/api/v1/admin/banners',
        queryParameters: query?.toJson(),
        options: Options(headers: await _getAuthHeaders()),
      );

      return AdminBannerListResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Gets a single banner with details.
  Future<AdminBannerDetail> getBanner(String id) async {
    try {
      final response = await _dio.get(
        '/api/v1/admin/banners/$id',
        options: Options(headers: await _getAuthHeaders()),
      );

      return AdminBannerDetail.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Creates a new banner.
  Future<Map<String, dynamic>> createBanner(AdminBannerRequest request) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners',
        data: request.toJson(),
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Updates an existing banner.
  Future<Map<String, dynamic>> updateBanner(
    String id,
    AdminBannerRequest request,
  ) async {
    try {
      final response = await _dio.put(
        '/api/v1/admin/banners/$id',
        data: request.toJson(),
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Deletes a banner.
  Future<void> deleteBanner(String id) async {
    try {
      await _dio.delete(
        '/api/v1/admin/banners/$id',
        options: Options(headers: await _getAuthHeaders()),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Publishes a banner.
  Future<Map<String, dynamic>> publishBanner(String id) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners/$id/publish',
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Pauses a banner.
  Future<Map<String, dynamic>> pauseBanner(String id) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners/$id/pause',
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Resumes a paused banner.
  Future<Map<String, dynamic>> resumeBanner(String id) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners/$id/resume',
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Archives a banner.
  Future<Map<String, dynamic>> archiveBanner(String id) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners/$id/archive',
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Duplicates a banner as a new draft.
  Future<Map<String, dynamic>> duplicateBanner(String id) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners/$id/duplicate',
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Previews a banner.
  Future<BannerPreviewResponse> previewBanner(BannerPreviewRequest request) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners/preview',
        data: request.toJson(),
        options: Options(headers: await _getAuthHeaders()),
      );

      return BannerPreviewResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Performs a bulk action on multiple campaigns.
  Future<Map<String, dynamic>> bulkAction(BulkCampaignAction action) async {
    try {
      final response = await _dio.post(
        '/api/v1/admin/banners/bulk',
        data: action.toJson(),
        options: Options(headers: await _getAuthHeaders()),
      );

      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Gets campaign metrics.
  Future<CampaignMetricsResponse> getCampaignMetrics(String campaignId) async {
    try {
      final response = await _dio.get(
        '/api/v1/admin/banners/$id/metrics',
        options: Options(headers: await _getAuthHeaders()),
      );

      return CampaignMetricsResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Gets the audit log for a campaign.
  Future<List<Map<String, dynamic>>> getAuditLog(String campaignId) async {
    try {
      final response = await _dio.get(
        '/api/v1/admin/banners/$id/audit',
        options: Options(headers: await _getAuthHeaders()),
      );

      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    // This would get the admin auth token
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Exception _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('error')) {
        return Exception(data['error'] as String? ?? 'Unknown error');
      }
    }
    return Exception(e.message ?? 'Unknown error');
  }
}