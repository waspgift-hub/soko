/// Centralized OTP verification models.
///
/// Every OTP flow in Soko Vibe (phone login, email login, phone/email
/// registration, phone/email password reset, account verification) is
/// expressed through [OtpVerificationRequest] and resolved through
/// [OtpVerificationResult]. The UI is shared; each flow supplies its own
/// backend verification operation via the controller/service layer.

/// Purpose of the OTP challenge. The purpose is bound to the verification
/// challenge server-side so a code issued for one purpose cannot be reused
/// for another (purpose-bound verification challenges).
enum OtpPurpose {
  phoneLogin,
  emailLogin,
  phoneRegister,
  emailRegister,
  phoneReset,
  emailReset,
  accountVerification,
}

/// Delivery channel for the OTP.
enum OtpChannel { phone, email }

extension OtpPurposeExt on OtpPurpose {
  OtpChannel get channel {
    switch (this) {
      case OtpPurpose.phoneLogin:
      case OtpPurpose.phoneRegister:
      case OtpPurpose.phoneReset:
        return OtpChannel.phone;
      case OtpPurpose.emailLogin:
      case OtpPurpose.emailRegister:
      case OtpPurpose.emailReset:
      case OtpPurpose.accountVerification:
        return OtpChannel.email;
    }
  }

  /// Human-readable label key used in headings/subtitles when the caller does
  /// not supply custom copy. The screen resolves this via context.tr().
  String get labelKey {
    switch (this) {
      case OtpPurpose.phoneLogin:
        return 'login_with_phone';
      case OtpPurpose.emailLogin:
        return 'login_with_email';
      case OtpPurpose.phoneRegister:
        return 'create_account';
      case OtpPurpose.emailRegister:
        return 'create_account';
      case OtpPurpose.phoneReset:
        return 'reset_password';
      case OtpPurpose.emailReset:
        return 'reset_password';
      case OtpPurpose.accountVerification:
        return 'verify_your_number';
    }
  }
}

/// Request sent to the universal [OtpVerificationScreen]. The caller owns
/// the backend verification operation and supplies it via [onVerify].
class OtpVerificationRequest {
  /// Purpose of the challenge (bound server-side).
  final OtpPurpose purpose;

  /// Full destination: E.164 phone (e.g. `+255712345678`) or email address.
  final String destination;

  /// Masked destination shown to the user (e.g. `+255 *** *** 482` or
  /// `u***@example.com`). Never exposes the complete contact unnecessarily.
  final String maskedDestination;

  /// Channel used for delivery.
  final OtpChannel channel;

  /// OTP length expected by the backend. Defaults to 6 but is configurable
  /// because the backend may issue different lengths per purpose.
  final int otpLength;

  /// Language code passed to the send-OTP endpoints.
  final String langCode;

  /// Called when the backend confirms a valid OTP. Receives [OtpVerificationResult].
  final Future<OtpVerificationResult> Function(String otp)? onVerify;

  /// Called when the user taps resend. Returns the new [OtpVerificationResult].
  final Future<OtpVerificationResult> Function()? onResend;

  /// Whether the user may edit the destination (phone/email) on this screen.
  final bool allowDestinationEdit;

  /// Whether resend is supported for this flow.
  final bool allowResend;

  /// Optional override for the screen heading.
  final String? headingOverride;

  /// Optional override for the explanation subtitle.
  final String? subtitleOverride;

  const OtpVerificationRequest({
    required this.purpose,
    required this.destination,
    required this.maskedDestination,
    required this.channel,
    this.otpLength = 6,
    this.langCode = 'sw',
    required this.onVerify,
    this.onResend,
    this.allowDestinationEdit = false,
    this.allowResend = true,
    this.headingOverride,
    this.subtitleOverride,
  });
}

/// Authoritative result of a verification attempt. The UI never synthesizes
/// a "verified" result locally — it only reflects what this model carries
/// after the backend has responded.
class OtpVerificationResult {
  /// Whether the backend accepted the OTP.
  final bool success;

  /// Machine-readable error code (e.g. `auth_otp_invalid`,
  /// `auth_otp_expired`, `auth_otp_rate_limited`, `auth_otp_send_failed`).
  final String? errorCode;

  /// Human-readable user-facing message (already localized by the caller).
  final String? userMessage;

  const OtpVerificationResult({
    required this.success,
    this.errorCode,
    this.userMessage,
  });

  const OtpVerificationResult.success() : this(success: true);

  const OtpVerificationResult.failure({
    required this.errorCode,
    required this.userMessage,
  }) : success = false;
}
