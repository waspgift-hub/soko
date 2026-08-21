import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

enum DsDividerStyle { solid, dashed, labeled }

class DsDivider extends StatelessWidget {
  final DsDividerStyle style;
  final double height;
  final double? thickness;
  final double indent;
  final double endIndent;
  final Color? color;
  final String? label;

  const DsDivider({
    super.key,
    this.style = DsDividerStyle.solid,
    this.height = 1,
    this.thickness,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    this.label,
  }) : assert(
          style != DsDividerStyle.labeled || label != null,
          'DsDividerStyle.labeled requires a label',
        );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.outlineVariant;

    if (style == DsDividerStyle.labeled && label != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s2),
        child: Row(
          children: [
            Expanded(
              child: Divider(
                height: height,
                thickness: thickness,
                indent: indent,
                endIndent: AppSpacing.s3,
                color: effectiveColor,
              ),
            ),
            Text(
              label!,
              style: TextStyle(
                fontSize: AppFontSize.xs,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            Expanded(
              child: Divider(
                height: height,
                thickness: thickness,
                indent: AppSpacing.s3,
                endIndent: endIndent,
                color: effectiveColor,
              ),
            ),
          ],
        ),
      );
    }

    if (style == DsDividerStyle.dashed) {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: (height - 1) / 2,
          horizontal: indent,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth - endIndent;
            return CustomPaint(
              size: Size(w > 0 ? w : 0, 1),
              painter: _DashedLinePainter(color: effectiveColor),
            );
          },
        ),
      );
    }

    return Divider(
      height: height,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      color: effectiveColor,
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
