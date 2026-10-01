import 'package:flutter/material.dart';

import '../ds/standard_input_field.dart';

/// Auth-surface input. Thin adapter over the design-system
/// [StandardInputField] so every field on login, register, forgot-password and
/// OTP screens shares one set of dimensions, padding and validation chrome.
///
/// This widget used to hand-roll its own glass container, floating label and a
/// hard-coded `contentPadding: EdgeInsets.symmetric(vertical: 22)`, which made
/// fields ~90dp tall — tall enough to overflow the register form once the
/// keyboard opened on a small phone, and duplicated for no reason what the DS
/// already owns ([DsFieldSize], [DsFieldVariant], focus/error animation).
/// Kept as a separate class because auth needs `autofillHints` and an explicit
/// suffix slot for the password / resend controls the DS does not own.
///
/// [DsFieldVariant.flat] is deliberate: auth fields sit on the raised AuthCard
/// surface, where the DS reserves its extruded shadow for flat backgrounds and
/// a second shadow would fight the card's own elevation.
class AuthTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final void Function(String)? onFieldSubmitted;
  final bool enabled;

  /// Density of the field. Defaults to [DsFieldSize.lg] because auth is a
  /// primary, thumb-driven surface — the one place a taller target is right.
  final DsFieldSize size;

  const AuthTextField({
    super.key,
    this.controller,
    this.focusNode,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.enabled = true,
    this.size = DsFieldSize.lg,
  });

  @override
  Widget build(BuildContext context) {
    return StandardInputField(
      controller: controller,
      focusNode: focusNode,
      label: label,
      hint: hint,
      prefixIcon: prefixIcon,
      suffix: suffix,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      onChanged: onChanged,
      onSubmitted: onFieldSubmitted,
      enabled: enabled,
      variant: DsFieldVariant.flat,
      size: size,
    );
  }
}
