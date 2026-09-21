import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';
import 'kyc_api.dart';
import '../utils/network_error.dart';

class KycService {
  /// One-time verification fee (TSh). Display fallback only — the server
  /// response from [getKycFeeStatus] is the source of truth.
  static const int feeAmount = 15000;

  static Future<Map<String, dynamic>?> submitKyc({
    required String userId,
    String? fullName,
    String? firstName,
    String? middleName,
    String? lastName,
    required String idType,
    required String idNumber,
    String? idImageUrl,
    String? selfieUrl,
    String? dateOfBirth,
    String? address,
    String? phone,
    String? email,
    String? shopVideoUrl,
  }) async {
    // fullName is derived from the three passport-style parts so the
    // combined name and the parts can never disagree server-side.
    final combined = fullName != null && fullName.trim().isNotEmpty
        ? fullName.trim()
        : [firstName, middleName, lastName]
            .map((s) => (s ?? '').trim())
            .where((s) => s.isNotEmpty)
            .join(' ');

    if (ApiConfig.kUseKycApi) {
      try {
        // userId is a Firebase UID; the server keys the row off the verified
        // token, so the body needs none of the legacy Firestore fields.
        return await KycApiClient().submit(
          fullName: combined,
          firstName: firstName,
          middleName: middleName,
          lastName: lastName,
          idType: idType,
          idNumber: idNumber,
          idImageUrl: idImageUrl,
          selfieUrl: selfieUrl,
          dateOfBirth: dateOfBirth,
          address: address,
          phone: phone,
          email: email,
          shopVideoUrl: shopVideoUrl,
        );
      } catch (e) {
        debugPrint('KycService.submitKyc (v1): $e');
        // fall through to legacy compat on transient failure
      }
    }
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/kyc/submit'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': userId,
          'fullName': combined,
          'firstName': firstName ?? '',
          'middleName': middleName ?? '',
          'lastName': lastName ?? '',
          'idType': idType,
          'idNumber': idNumber,
          'idImageUrl': idImageUrl ?? '',
          'selfieUrl': selfieUrl ?? '',
          'dateOfBirth': dateOfBirth ?? '',
          'address': address ?? '',
          'phone': phone ?? '',
          'email': email ?? '',
          'shopVideoUrl': shopVideoUrl ?? '',
        }),
      );
      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        return {'success': false, 'error': body['error'] ?? 'Unknown error'};
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('KycService.submitKyc: $e');
      return {'success': false, 'error': translateError(e)};
    }
  }

  static Future<Map<String, dynamic>?> getKycStatus(String userId) async {
    if (ApiConfig.kUseKycApi) {
      try {
        return await KycApiClient().fetchStatus(userId);
      } catch (e) {
        debugPrint('KycService.getKycStatus (v1): $e');
        // fall through to legacy compat on transient failure
      }
    }
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/kyc/status/$userId'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('KycService.getKycStatus: $e');
      return null;
    }
  }

  /// Whether the caller's one-time verification fee is settled.
  ///
  /// v1 only — the legacy stack has no fee concept. A v1 failure returns
  /// `{paid: false, error: true}` so the screen can offer a retry instead of
  /// silently treating an outage as "unpaid".
  static Future<Map<String, dynamic>> getKycFeeStatus() async {
    try {
      return await KycApiClient().fetchFeeStatus();
    } catch (e) {
      debugPrint('KycService.getKycFeeStatus: $e');
      return {'paid': false, 'amount': feeAmount, 'error': true};
    }
  }

  /// Starts a ClickPesa collection for the one-time fee.
  ///
  /// `paymentMethod` is 'ussd_push' (default) or 'billpay'. Returns
  /// `{success: true, ...serverData}` or `{success: false, error}`.
  static Future<Map<String, dynamic>> initiateKycFee({
    required String phone,
    String paymentMethod = 'ussd_push',
  }) async {
    try {
      return await KycApiClient()
          .initiateFee(phone: phone, paymentMethod: paymentMethod);
    } catch (e) {
      debugPrint('KycService.initiateKycFee: $e');
      return {'success': false, 'error': translateError(e)};
    }
  }

  /// Sends a 6-digit OTP to the seller's phone (SMS) via /api/v1/kyc.
  ///
  /// Returns `{success, sent, expiresInSec}`. `sent:false` means the SMS
  /// provider rejected it even though the server stored the code.
  static Future<Map<String, dynamic>> sendPhoneOtp(String phone) {
    return _otpCall('KycService.sendPhoneOtp',
        () => KycApiClient().sendPhoneOtp(phone));
  }

  /// Confirms the phone OTP sent by [sendPhoneOtp].
  static Future<Map<String, dynamic>> verifyPhoneOtp(
      String phone, String otp) {
    return _otpCall(
        'KycService.verifyPhoneOtp',
        () => KycApiClient().verifyPhoneOtp(phone: phone, otp: otp));
  }

  /// Sends a 6-digit OTP to the seller's email via /api/v1/kyc.
  static Future<Map<String, dynamic>> sendEmailOtp(String email) {
    return _otpCall('KycService.sendEmailOtp',
        () => KycApiClient().sendEmailOtp(email));
  }

  /// Confirms the email OTP sent by [sendEmailOtp].
  static Future<Map<String, dynamic>> verifyEmailOtp(
      String email, String otp) {
    return _otpCall(
        'KycService.verifyEmailOtp',
        () => KycApiClient().verifyEmailOtp(email: email, otp: otp));
  }

  static Future<Map<String, dynamic>> _otpCall(
    String tag,
    Future<Map<String, dynamic>> Function() call,
  ) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('$tag: $e');
      return {'success': false, 'error': translateError(e)};
    }
  }
}