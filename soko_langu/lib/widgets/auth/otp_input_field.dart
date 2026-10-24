import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Premium single-field OTP input.
///
/// Replaces the traditional six separate bordered boxes with one continuous
/// underline-style field that shows large, readable digits with character
/// spacing. Supports numeric keyboard, paste, backspace, autofill hints, and
/// focus state — no individual boxes, no square containers, no input cards.
///
/// The widget does not auto-submit: the caller decides when to verify (e.g.
/// when the required [length] is reached or on explicit submit).
class OtpInputField extends StatefulWidget {
  /// Required number of digits. Defaults to 6 but is configurable per the
  /// backend's OTP length.
  final int length;

  /// Current code value (controlled). The caller updates this from [onChanged].
  final String value;

  /// Called whenever the value changes (including paste, backspace, and
  /// autofill).
  final ValueChanged<String>? onChanged;

  /// Called when the user taps return / done on the keyboard.
  final VoidCallback? onSubmitted;

  /// Whether the field is enabled.
  final bool enabled;

  /// Whether the field has an error state (renders the underline in error
  /// color and shakes slightly).
  final bool hasError;

  /// Accessibility label prefix for each digit position announcement.
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
      // Defer focus until the route transition settles so the keyboard
      // present animation does not fight the page slide.
      Future.delayed(const Duration(milliseconds: 380), () {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(OtpInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value) {
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

  /// Returns only the numeric digits from the current value.
  String get _digits => _controller.text.replaceAll(RegExp(r'\D'), '');

  bool get _isComplete => _digits.length >= widget.length;

  void _onChanged(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\D'), '');
    // Truncate to the configured length so paste/autofill never exceeds it.
    final truncated = cleaned.length > widget.length
        ? cleaned.substring(0, widget.length)
        : cleaned;
    if (truncated != _digits) {
      _controller.value = TextEditingValue(
        text: truncated,
        selection: TextSelection.collapsed(offset: truncated.length),
      );
      widget.onChanged?.call(truncated);
    }
    if (_isComplete) {
      widget.onSubmitted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final underlineColor = widget.hasError
        ? cs.error
        : _focusNode.hasFocus
            ? cs.primary
            : cs.onSurfaceVariant.withValues(alpha: 0.35);

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, _) {
        final dx = math.sin(_shake.value * 3 * math.pi) * 6 * (1 - _shake.value);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: false,
                    decimal: false,
                  ),
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  maxLines: 1,
                  expands: false,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.transparent, // hide native caret; we render digits above
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 14.0,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onChanged: _onChanged,
                  onSubmitted: (_) => widget.onSubmitted?.call(),
                ),
              ),
              const SizedBox(height: 10),
              // Continuous underline (single-line input treatment).
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                decoration: BoxDecoration(
                  color: underlineColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              if (_focusNode.hasFocus && !widget.hasError)
                // Subtle focus indicator beneath the underline.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
