import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// Opens the system dialer with a number prefilled. The call is placed over
/// the normal cellular network using the caller's minutes/balance — no
/// internet, no data. We use ACTION_DIAL (dialer) instead of ACTION_CALL, so
/// no CALL_PHONE permission is required and the user confirms the call.
class CallService {
  CallService._();

  /// Returns false if there is no dialer on the device or the number is empty.
  static Future<bool> dial(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return false;
    final uri = Uri(scheme: 'tel', path: digits);
    if (!await url_launcher.canLaunchUrl(uri)) return false;
    return await url_launcher.launchUrl(uri, mode: url_launcher.LaunchMode.externalApplication);
  }
}
