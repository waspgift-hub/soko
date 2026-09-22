import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Primary (black) and secondary (outline) CTAs with hover/press feedback.
class PremiumButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;

  const PremiumButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = true,
    this.icon,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.primary ? SokoBrand.black : SokoBrand.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 17),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: widget.primary
                  ? null
                  : Border.all(color: SokoBrand.ink, width: 1.2),
              boxShadow: _hover && widget.primary
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: widget.primary
                        ? SokoBrand.white
                        : SokoBrand.ink,
                  ),
                ),
                if (widget.icon != null) ...[
                  const SizedBox(width: 8),
                  AnimatedSlide(
                    offset: Offset(_hover ? 0.25 : 0, 0),
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: widget.primary
                          ? SokoBrand.white
                          : SokoBrand.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
