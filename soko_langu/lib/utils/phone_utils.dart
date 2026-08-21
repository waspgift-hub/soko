class PhoneUtils {
  PhoneUtils._();

  static String formatForDisplay(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('0')) {
      return '${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
    }
    if (digits.length == 12 && digits.startsWith('255')) {
      final local = '0${digits.substring(3)}';
      return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
    }
    if (digits.length == 13 && digits.startsWith('255')) {
      final local = '0${digits.substring(3)}';
      return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
    }
    return phone;
  }

  static String sanitizeForWhatsApp(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    } else if (cleaned.startsWith('0')) {
      cleaned = '255${cleaned.substring(1)}';
    }
    if (!cleaned.startsWith('255')) {
      cleaned = '255$cleaned';
    }
    return cleaned;
  }

  static String normalizeToLocal(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('255') && digits.length >= 12) {
      return '0${digits.substring(3)}';
    }
    if (digits.startsWith('0') && digits.length == 10) {
      return digits;
    }
    return digits;
  }

  /// Normalizes any Tanzanian phone format (07.., +255..., 255...) to E.164.
  static String toE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) return '255${digits.substring(1)}';
    if (digits.startsWith('255')) return digits;
    return '255$digits';
  }

  /// Normalizes a raw local-format number against an explicit country dial
  /// code (e.g. `071 234 5678` + `255` -> `255712345678`).
  static String toE164WithDial(String raw, String dial) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!digits.startsWith(dial)) digits = '$dial$digits';
    return digits;
  }

  /// Formats an E.164 number for display prefixed with its dial code,
  /// e.g. `+255 712 345 678`.
  static String displayWithDial(String e164, String dial) {
    final local = normalizeToLocal(e164);
    final pretty = formatForDisplay(local);
    final trimmed = pretty.startsWith('0') ? pretty.substring(1) : pretty;
    return '+$dial $trimmed';
  }
}
