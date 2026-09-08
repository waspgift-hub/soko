import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

/// Premium rounded search field used by every search surface.
///
/// Long localized hints are ellipsized instead of overflowing the field.
/// Optional [trailing] actions (voice, barcode, filters) render as 40dp icon
/// buttons that never push the field out of bounds. When a [controller] and
/// [onClear] are set, a clear button appears only while the field has text.
class SokoSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final VoidCallback? onFilter;
  final bool filterActive;
  final List<Widget>? trailing;
  final bool autofocus;
  final String? semanticsLabel;

  const SokoSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = '',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.onFilter,
    this.filterActive = false,
    this.trailing,
    this.autofocus = false,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final trailingCount = (trailing?.length ?? 0) + (onFilter != null ? 1 : 0) + (onClear != null ? 1 : 0);
    final suffix = trailingCount > 0
        ? _SuffixRow(
            trailing: trailing,
            onFilter: onFilter,
            filterActive: filterActive,
            onClear: onClear,
            controller: controller,
            filterButton: _filterButton(context, cs),
          )
        : null;

    return Semantics(
      textField: true,
      label: semanticsLabel ?? (hint.isEmpty ? null : hint),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: AppFontSize.md, color: cs.onSurface),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: AppFontSize.md, color: cs.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
          suffixIconConstraints: trailingCount > 0
              ? const BoxConstraints(minWidth: 0, minHeight: 0)
              : null,
          suffixIcon: suffix,
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
          ),
        ),
      ),
    );
  }

  Widget _filterButton(BuildContext context, ColorScheme cs) {
    return IconButton(
      onPressed: onFilter,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      tooltip: 'Filter',
      icon: Icon(
        Icons.tune_rounded,
        size: 20,
        color: filterActive ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }
}

/// Rebuilds only the trailing row when the controller text changes, so the
/// clear button appears/disappears without rebuilding the whole field.
class _SuffixRow extends StatelessWidget {
  final List<Widget>? trailing;
  final VoidCallback? onFilter;
  final bool filterActive;
  final VoidCallback? onClear;
  final TextEditingController? controller;
  final Widget filterButton;

  const _SuffixRow({
    this.trailing,
    this.onFilter,
    this.filterActive = false,
    this.onClear,
    this.controller,
    required this.filterButton,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget row() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...?trailing,
          if (onFilter != null) filterButton,
        ],
      );
    }

    if (onClear == null || controller == null) return row();

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller!,
      builder: (context, value, _) {
        if (value.text.isEmpty) return row();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.close_rounded, size: 18, color: cs.onSurfaceVariant),
            ),
            ...?trailing,
            if (onFilter != null) filterButton,
          ],
        );
      },
    );
  }
}