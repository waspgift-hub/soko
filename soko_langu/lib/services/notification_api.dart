import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/notification_item.dart';
import 'api_config.dart';
import '../utils/network_error.dart';

/// Server-backed notification center client (`/api/v1/notifications`).
///
/// Reads the persistent in-app notification inbox from Postgres instead of
/// Firestore. Push delivery (OneSignal) is unchanged — only the notification
/// history/log migrates. The flag [ApiConfig.kUseNotificationsApi] controls
/// when the app switches from Firestore to this client.
class NotificationApiClient {
  final http.Client _http;
  final Future<String?> Function() _token;

  NotificationApiClient({
    http.Client? httpClient,
    Future<String?> Function()? tokenProvider,
  }) : _http = httpClient ?? http.Client(),
       _token = tokenProvider ?? _defaultToken;

  static Future<String?> _defaultToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  /// Returns paginated notifications (newest first) + unread count.
  Future<({List<NotificationItem> notifications, int unreadCount})>
  fetchNotifications({int page = 1, int limit = 20}) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    final uri = Uri.parse(
      ApiConfig.v1('/notifications'),
    ).replace(queryParameters: params);

    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw _errorFor(res, action: 'fetch notifications');
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};

    final items = (data['notifications'] is List)
        ? (data['notifications'] as List)
              .whereType<Map<String, dynamic>>()
              .map(_parseItem)
              .toList()
        : const <NotificationItem>[];

    final unread = await fetchUnreadCount();

    return (notifications: items, unreadCount: unread);
  }

  /// Fetches the unread notification count.
  Future<int> fetchUnreadCount() async {
    final uri = Uri.parse(ApiConfig.v1('/notifications/unread-count'));
    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return 0;

    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  /// Marks a single notification as read. Returns true if it existed.
  Future<bool> markRead(String notificationId) async {
    final uri = Uri.parse(
      ApiConfig.v1('/notifications/$notificationId/read'),
    );
    final res = await _http
        .post(uri, headers: await _headers())
        .timeout(const Duration(seconds: 10));
    return res.statusCode == 200;
  }

  /// Marks all of the user's notifications as read. Returns the count marked.
  Future<int> markAllRead() async {
    final uri = Uri.parse(ApiConfig.v1('/notifications/read-all'));
    final res = await _http
        .post(uri, headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return 0;
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    return (data['marked'] as num?)?.toInt() ?? 0;
  }

  /// Deletes a single notification. Returns true if it existed.
  Future<bool> delete(String notificationId) async {
    final uri = Uri.parse(
      ApiConfig.v1('/notifications/$notificationId'),
    );
    final res = await _http
        .delete(uri, headers: await _headers())
        .timeout(const Duration(seconds: 10));
    return res.statusCode == 200;
  }

  /// Deletes all of the user's notifications. Returns the count deleted.
  Future<int> deleteAll() async {
    final uri = Uri.parse(ApiConfig.v1('/notifications'));
    final res = await _http
        .delete(uri, headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return 0;
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final data = body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    return (data['deleted'] as num?)?.toInt() ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static NotificationItem _parseItem(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : <String, dynamic>{};
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'general',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      isRead: json['isRead'] == true,
      otherUserId: data['senderId']?.toString(),
      otherUserName: data['senderName']?.toString(),
      otherUserImage: data['senderImage']?.toString(),
      productId: data['productId']?.toString(),
      productImage: data['productImage']?.toString(),
    );
  }

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    if (token == null) {
      throw NetworkError(
        message: 'Notification request requires auth',
        userMessage: ErrorKeys.sessionExpired,
      );
    }
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static NetworkError _errorFor(http.Response res, {required String action}) {
    final userMessage = switch (res.statusCode) {
      401 => ErrorKeys.sessionExpired,
      403 => ErrorKeys.noPermission,
      404 => ErrorKeys.notFound,
      _ => ErrorKeys.generic,
    };
    return NetworkError(
      message: 'Notification $action failed: ${res.statusCode}',
      userMessage: userMessage,
    );
  }
}
