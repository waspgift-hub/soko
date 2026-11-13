class Validators {
  static String? email(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!regex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (!isStrongPassword(value)) return 'Min 8 characters with letters and numbers';
    return null;
  }

  // Mirrors the server password policy (min length + letter + digit) so weak
  // passwords are rejected on the device instead of a server round-trip.
  static bool isStrongPassword(String value) {
    if (value.length < 8) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) return false;
    if (!RegExp(r'[0-9]').hasMatch(value)) return false;
    return true;
  }

  static String? phone(String? value) {
    if (value == null || value.isEmpty) return 'Phone is required';
    final regex = RegExp(r'^0[67]\d{8}$');
    if (!regex.hasMatch(value)) {
      return 'Enter a valid Tanzanian phone (e.g. 0712345678)';
    }
    return null;
  }

  static String? required(String? value, [String field = 'This field']) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? number(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    if (double.tryParse(value) == null) return 'Enter a valid number';
    return null;
  }
}
