import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../ds/ds.dart';

/// Option entry for [SokoDropdown].
class SokoDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SokoDropdownItem({required this.value, required this.label, this.icon});
}

/// Premium single-select dropdown that opens a scroll-safe [DsSheet] list.
///
/// Supports long translated labels and any number of items — the sheet scrolls
/// at 85% height. No overflow risk on any screen size.
class SokoDropdown<T> extends StatelessWidget {
  final T? value;
  final List<SokoDropdownItem<T>> items;
  final ValueChanged<T>? onChanged;
  final String? hint;
  final String? label;
  final bool enabled;
  final String? errorText;

  const SokoDropdown({
    super.key,
    this.value,
    required this.items,
    this.onChanged,
    this.hint,
    this.label,
    this.enabled = true,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedItem = items.cast<SokoDropdownItem<T>?>().firstWhere(
          (i) => i?.value == value,
          orElse: () => null,
        );

    return GestureDetector(
      onTap: enabled ? () => _openSheet(context) : null,
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          enabled: enabled,
          labelText: label,
          hintText: hint,
          errorText: errorText,
          filled: true,
          fillColor: enabled
              ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          prefixIcon: selectedItem?.icon != null
              ? Icon(selectedItem!.icon, size: 20)
              : null,
          suffixIcon: Icon(
            Icons.unfold_more_rounded,
            size: 20,
            color: enabled ? cs.onSurfaceVariant : cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: cs.brandBorder, width: 1),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: cs.brandBorder.withValues(alpha: 0.4), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: cs.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: cs.error, width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s3,
          ),
        ),
        child: Text(
          selectedItem?.label ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppFontSize.md,
            color: value == null ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    DsSheet.show(
      context: context,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s3),
              child: Text(
                label!,
                style: TextStyle(
                  fontSize: AppFontSize.lg,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (_, i) {
                final item = items[i];
                final selected = item.value == value;
                return AnimatedPress(
                  onTap: () {
                    Navigator.of(context).pop();
                    onChanged?.call(item.value);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                      vertical: AppSpacing.s3,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? cs.primary.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        if (item.icon != null) ...[
                          Icon(
                            item.icon,
                            size: 20,
                            color: selected ? cs.primary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.s3),
                        ],
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppFontSize.md,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected ? cs.primary : cs.onSurface,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_rounded, size: 18, color: cs.primary),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}