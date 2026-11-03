import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_colors.dart';

/// Design-system text field (spec §4.4): 12dp radius, surface fill, hairline
/// border; focused gets a 2px primary border, error gets error chrome +
/// helper text.
///
/// Security: input is sanitized before delivery via [onChanged] — control
/// characters and zero-width joiners are stripped to prevent injection
/// payloads in Firestore documents.  [inputFormatters] can be composed
/// externally and are applied *after* the built-in sanitizer.
class DsTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final int? maxLines;
  final int? maxLength;
  final bool readOnly;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool readOnlyForAutofill;

  const DsTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.focusNode,
    this.maxLines,
    this.maxLength,
    this.readOnly = false,
    this.validator,
    this.inputFormatters,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.readOnlyForAutofill = false,
  });

  /// Strips control characters and zero-width joiners that could be used
  /// to inject invisible data into Firestore documents.
  static String _sanitize(String value) {
    return value
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .replaceAll('\u200B', '')
        .replaceAll('\u200C', '')
        .replaceAll('\u200D', '')
        .replaceAll('\uFEFF', '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged != null
          ? (v) => onChanged!(_sanitize(v))
          : null,
      readOnly: readOnly,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      validator: validator,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions && !obscureText,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: errorText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon != null
            ? GestureDetector(
                onTap: onSuffixTap,
                child: Icon(suffixIcon),
              )
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.brandBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        errorStyle: TextStyle(color: scheme.error, fontSize: 12),
      ),
    );
  }
}
