import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Design-system bottom sheet (spec §4.2): 24dp top radius, grabber,
/// drag-to-dismiss, max 85% height, 24dp content padding.
class DsSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showGrabber;

  const DsSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.s6),
    this.showGrabber = true,
  });

  /// Presents [content] as a modal sheet with the standard chrome.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget content,
    EdgeInsetsGeometry padding = const EdgeInsets.all(AppSpacing.s6),
    bool showGrabber = true,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (context) => DsSheet(
        padding: padding,
        showGrabber: showGrabber,
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceLight,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius2.xxl),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.brandTextPrimary.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showGrabber) ...[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.brandTextSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
