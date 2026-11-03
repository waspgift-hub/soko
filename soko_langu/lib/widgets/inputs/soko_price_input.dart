import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Currency-prefixed numeric field for marketplace price entry.
///
/// Shows the active currency symbol, uses `TextInputType.numberWithOptions` and
/// sanitizes injection payloads like [DsTextField].
class SokoPriceInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final bool readOnly;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? extraFormatters;

  const SokoPriceInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.readOnly = false,
    this.focusNode,
    this.onChanged,
    this.validator,
    this.extraFormatters,
  });

  static String _sanitize(String v) =>
      v.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
          .replaceAll('\u200B', '')
          .replaceAll('\u200C', '')
          .replaceAll('\u200D', '')
          .replaceAll('\uFEFF', '');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final symbol = context.currencySymbol();
    final formatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ...?extraFormatters,
    ];

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
      onChanged: onChanged != null ? (v) => onChanged!(_sanitize(v)) : null,
      validator: validator,
      inputFormatters: formatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: errorText,
        prefixText: '$symbol ',
        prefixStyle: TextStyle(
          fontSize: AppFontSize.md,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
        filled: true,
        fillColor: readOnly
            ? cs.surfaceContainerHighest.withValues(alpha: 0.3)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.brandBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s3,
        ),
      ),
    );
  }
}