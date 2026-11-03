import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

/// Responsive product grid that adapts column count from 2 to 4 based on width.
///
/// Wraps a grid of [child] widgets with consistent spacing, clamped to a
/// comfortable reading width. Infinite height is not allowed.
class ProductGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double spacing;
  final double runSpacing;
  final double? maxWidth;
  final double childAspectRatio;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final ScrollController? controller;

  const ProductGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = AppSpacing.s3,
    this.runSpacing = AppSpacing.s3,
    this.maxWidth,
    this.childAspectRatio = 0.55,
    this.physics,
    this.shrinkWrap = false,
    this.controller,
  });

  static int _columnsForWidth(double width) {
    if (width >= 960) return 5;
    if (width >= 720) return 4;
    if (width >= 480) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = maxWidth != null && constraints.maxWidth > maxWidth!
            ? maxWidth!
            : constraints.maxWidth;
        final cols = _columnsForWidth(width);

        return GridView.builder(
          controller: controller,
          physics: physics ?? const NeverScrollableScrollPhysics(),
          shrinkWrap: shrinkWrap,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: runSpacing,
            crossAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// Horizontal product list with uniform card widths.
class ProductList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double spacing;
  final double itemWidth;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;

  const ProductList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = AppSpacing.s3,
    this.itemWidth = 150,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemWidth * 1.6,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        physics: physics ?? const BouncingScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, _) => SizedBox(width: spacing),
        itemBuilder: (context, index) => SizedBox(width: itemWidth, child: itemBuilder(context, index)),
      ),
    );
  }
}
