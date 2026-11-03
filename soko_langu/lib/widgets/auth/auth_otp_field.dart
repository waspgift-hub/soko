import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';

/// Six-box OTP entry with auto-advance, backspace navigation, paste support,
/// numeric keyboard and auto-submit when every box is filled.
///
/// Increment [errorTick] to flash the boxes red and shake them; the value is
/// intentionally opaque because the screen owns the error message state.
class AuthOtpField extends StatefulWidget {
  final int length;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;
  final bool enabled;
  final int errorTick;
  final double boxSize;

  const AuthOtpField({
    super.key,
    this.length = 6,
    this.onCompleted,
    this.autofocus = true,
    this.enabled = true,
    this.errorTick = 0,
    this.boxSize = 52,
  });

  @override
  State<AuthOtpField> createState() => AuthOtpFieldState();
}

class AuthOtpFieldState extends State<AuthOtpField>
    with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    if (widget.autofocus) {
      // Defer until the route transition settles so the keyboard present
      // animation does not fight the page slide.
      Future.delayed(const Duration(milliseconds: 380), () {
        if (mounted) _focusNodes.first.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(AuthOtpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.errorTick != widget.errorTick && widget.errorTick > 0) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _shake.dispose();
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  bool get _isComplete =>
      _controllers.every((c) => c.text.isNotEmpty) &&
      _code.length == widget.length;

  String get code => _code;

  bool get isComplete => _isComplete;

  /// Programmatically fills the boxes from a clipboard code and submits.
  void setCode(String rawCode) {
    final digits = rawCode.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    _distribute(digits);
  }

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    setState(() {});
  }

  void _notifyCompletion() {
    if (_isComplete) {
      widget.onCompleted?.call(_code);
    }
  }

  void _onChanged(int index, String value) {
    final cleaned = value.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length > 1) {
      _distribute(cleaned);
      return;
    }
    _controllers[index].text = cleaned;
    if (cleaned.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
    _notifyCompletion();
  }

  void _distribute(String value) {
    for (var i = 0; i < widget.length; i++) {
      _controllers[i].text = i < value.length ? value[i] : '';
    }
    final next = value.length < widget.length ? value.length : widget.length - 1;
    _focusNodes[next].requestFocus();
    setState(() {});
    _notifyCompletion();
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isNotEmpty) {
      _controllers[index].clear();
      setState(() {});
    } else if (index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, _) {
        final dx = math.sin(_shake.value * 3 * math.pi) * 8 * (1 - _shake.value);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.length, (index) {
              final borderColor = !widget.enabled
                  ? cs.brandBorder
                  : widget.errorTick > 0
                      ? cs.error
                      : cs.brandBorder;
              return SizedBox(
                width: widget.boxSize,
                height: widget.boxSize * 1.25,
                child: AnimatedContainer(
                  duration: Motion.cardPress,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: borderColor,
                      width: 1.5,
                    ),
                    boxShadow: widget.errorTick > 0
                        ? [BoxShadow(color: cs.error.withValues(alpha: 0.18), blurRadius: 16)]
                        : null,
                  ),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      final isBackspace =
                          event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.backspace;
                      if (isBackspace && _controllers[index].text.isEmpty) {
                        _onBackspace(index);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      onChanged: (value) => _onChanged(index, value),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: cs.onSurface,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}