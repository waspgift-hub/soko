import 'package:flutter/material.dart';
import '../ds/ds.dart';

/// Premium add-to-cart button with animated states.
///
/// Transitions between: idle (outline), pressed (filled), and success (check).
/// The success state auto-reverts after [successDuration].
class AddToCartButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool enabled;
  final bool showSuccess;
  final Duration successDuration;

  const AddToCartButton({
    super.key,
    this.onPressed,
    this.enabled = true,
    this.showSuccess = false,
    this.successDuration = const Duration(seconds: 2),
  });

  @override
  State<AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<AddToCartButton> with SingleTickerProviderStateMixin {
  bool _success = false;
  AnimationController? _revertController;

  @override
  void initState() {
    super.initState();
    _success = widget.showSuccess;
    if (_success) _startRevertTimer();
  }

  @override
  void didUpdateWidget(covariant AddToCartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showSuccess && !oldWidget.showSuccess) {
      setState(() => _success = true);
      _startRevertTimer();
    }
  }

  void _startRevertTimer() {
    _revertController?.stop();
    _revertController?.dispose();
    _revertController = AnimationController(vsync: this, duration: widget.successDuration);
    _revertController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _success = false);
      }
    });
    _revertController!.forward();
  }

  @override
  void dispose() {
    _revertController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onPressed != null;

    return DsButton(
      onPressed: enabled
          ? () {
              widget.onPressed?.call();
              setState(() => _success = true);
              _startRevertTimer();
            }
          : null,
      variant: _success ? DsButtonVariant.tonal : DsButtonVariant.secondary,
      size: DsButtonSize.sm,
      fullWidth: false,
      icon: _success ? Icons.check_rounded : Icons.shopping_cart_outlined,
      label: _success ? 'Added' : 'Add to Cart',
    );
  }
}
