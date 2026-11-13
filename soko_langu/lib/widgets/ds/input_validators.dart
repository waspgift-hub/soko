/// Pure, side-effect-free validators shared by every Soko Vibe form.
///
/// Each helper returns `null` when the value is acceptable and a human-readable
/// message otherwise, which is the contract [FormFieldState.validator] expects.
///
/// Validators are called on every keystroke when a field renders its success
/// indicator, so they must stay pure: no I/O, no `context`, no translation lookups
/// that depend on mutable state. Pass already-translated messages in.
class DsValidators {
  DsValidators._();

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Accepts local Tanzanian formats (`07…`, `2557…`, `+2557…`) with spaces or
  /// dashes stripped, so pasted numbers are not rejected on formatting alone.
  static final RegExp _phone = RegExp(r'^\+?255\d{9}$');

  static String? required(String? value, {String message = 'Required'}) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String? email(String? value, {String message = 'Invalid email'}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return message;
    return _email.hasMatch(v) ? null : message;
  }

  /// 8-character floor matches the signup rule enforced in `register_screen`;
  /// 9 digits matches the minimum subscriber number validated there.
  static String? password(
    String? value, {
    String emptyMessage = 'Enter your password',
    String shortMessage = 'Use at least 8 characters',
  }) {
    final v = value ?? '';
    if (v.isEmpty) return emptyMessage;
    if (v.length < 8) return shortMessage;
    return null;
  }

  static String? phone(
    String? value, {
    String message = 'Enter a valid phone number',
  }) {
    final digits = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (digits.isEmpty) return message;
    if (digits.startsWith('0')) {
      return digits.length == 10 ? null : message;
    }
    return _phone.hasMatch(digits) ? null : message;
  }

  static String? minLength(
    int length,
    String? value, {
    String message = 'Too short',
  }) {
    if ((value ?? '').trim().length < length) return message;
    return null;
  }

  static String? maxLength(
    int length,
    String? value, {
    String message = 'Too long',
  }) {
    if ((value ?? '').trim().length > length) return message;
    return null;
  }

  static String? numeric(
    String? value, {
    bool allowDecimal = false,
    String message = 'Numbers only',
  }) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return message;
    final pattern = allowDecimal ? r'^\d+([.,]\d+)?$' : r'^\d+$';
    return RegExp(pattern).hasMatch(v) ? null : message;
  }

  /// Runs validators in order and returns the first failure, so one `validator:`
  /// slot can cover "required + shape + length" without nesting closures at
  /// every call site.
  static String? Function(String?)? compose(
    List<String? Function(String?)> validators,
  ) {
    return (value) {
      for (final validate in validators) {
        final error = validate(value);
        if (error != null) return error;
      }
      return null;
    };
  }

  /// Cross-field check (confirm password, matching OTP). [other] is read lazily
  /// so the comparison always sees the current controller value.
  static String? match(
    String? value,
    String? Function() other, {
    String message = 'Values do not match',
  }) {
    if (value == null) return message;
    return value == other() ? null : message;
  }
}
