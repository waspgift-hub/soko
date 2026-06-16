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
}
