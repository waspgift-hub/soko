import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Six separate boxes OTP input.
///
/// Renders one bordered box per digit. A single underlying [TextField] owns
/// all keyboard, paste and autofill handling so a paste of the full code fills
/// every box at once; the boxes are visual only and reflect the current value.
/// Auto-advance is implicit (typing keeps appending) and auto-submit fires via
/// [onSubmitted] once [length] digits are entered.
class OtpInputField extends StatefulWidget {
  final int length;
  final String value;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final bool enabled;
  final bool hasError;
  final String digitPositionLabel;

  const OtpInputField({
    super.key,
    this.length = 6,
    this.value = '',
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.hasError = false,
    this.digitPositionLabel = 'Nafasi ya namba',
  }) : assert(length > 0 && length <= 12);

  @override
  State<OtpInputField> createState() => _OtpInputFieldState();
}

class _OtpInputFieldState extends State<OtpInputField>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    if (widget.enabled) {
      Future.delayed(const Duration(milliseconds: 380), () {
        if (mounted) _focusNode.requestFocus();
      });
    }
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(OtpInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
    if (oldWidget.hasError != widget.hasError && widget.hasError) {
      _shake.forward(from: 0);
    }
    if (oldWidget.enabled != widget.enabled && widget.enabled) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _shake.dispose();
    super.dispose();
  }

  String get _digits => _controller.text.replaceAll(RegExp(r'\D'), '');

  void _onChanged(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\D'), '');
    final truncated = cleaned.length > widget.length
        ? cleaned.substring(0, widget.length)
        : cleaned;
    if (truncated != _controller.text) {
      _controller.value = TextEditingValue(
        text: truncated,
        selection: TextSelection.collapsed(offset: truncated.length),
      );
    }
    widget.onChanged?.call(truncated);
    if (truncated.length == widget.length) {
      widget.onSubmitted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final focusIndex = _focusNode.hasFocus ? _digits.length.clamp(0, widget.length - 1) : -1;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, _) {
        final dx = math.sin(_shake.value * 3 * math.pi) * 6 * (1 - _shake.value);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(widget.length, (i) {
                  final filled = i < _digits.length;
                  final isFocus = i == focusIndex;
                  final borderColor = widget.hasError
                      ? cs.error
                      : isFocus
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.35);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor, width: isFocus ? 2 : 1.5),
                          ),
                          child: Text(
                            filled ? _digits[i] : '',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: widget.hasError ? cs.error : cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              // Invisible input layer owns keyboard, paste and autofill.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(border: InputBorder.none),
                    onChanged: _onChanged,
                    onSubmitted: (_) => widget.onSubmitted?.call(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}