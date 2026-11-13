import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../theme/neumorphic.dart';

/// Visual state a [StandardInputField] renders. Derived internally from focus,
/// validation and value — exposed so screens and tests can assert on it.
enum DsFieldStatus { idle, focused, error, success, disabled }

enum DsFieldVariant {
  /// Extruded (soft elevation) — the default commerce look: dual neumorphic
  /// shadows from one top-left light source.
  soft,

  /// Recessed field: darker base plus a groove, for dense filters and search.
  inset,

  /// Border only, no shadow — for cards that already sit on a raised surface.
  flat,
}

enum DsFieldSize { sm, md, lg }

/// Intent-level keyboard selection. Each value resolves to the platform
/// [TextInputType], autocorrect rules, [TextInputFormatter]s, autofill hints and
/// text capitalisation that the intent implies, so call sites never assemble
/// them by hand.
enum DsKeyboard {
  text,
  email,
  phone,
  number,
  decimal,
  password,
  multiline,
  search,
}

/// Package-private bundle of everything a [DsKeyboard] implies.
class _KeyboardSpec {
  final TextInputType type;
  final TextCapitalization capitalization;
  final bool autocorrect;
  final bool suggestions;
  final List<String>? autofillHints;
  final List<TextInputFormatter> formatters;
  final TextInputAction? action;

  const _KeyboardSpec({
    required this.type,
    required this.capitalization,
    required this.autocorrect,
    required this.suggestions,
    this.autofillHints,
    this.formatters = const [],
    this.action,
  });
}

/// Design-system text input — the single field every Soko Vibe form surface
/// uses (auth, profile, checkout, search, KYC, seller forms).
///
/// Built on a borderless [TextField] inside an animated container so the
/// neumorphic chrome (edge colour, dual shadow, glow) can be tweened; the field
/// itself never draws a border. Validation is owned by a [FormField] wrapper so
/// the error chrome appears at the same moment as the message — including when
/// an ancestor `Form.validate()` runs.
///
/// States:
/// - idle — hairline edge, soft extruded shadow
/// - focused — primary edge plus a tinted glow, animated
/// - error — error edge, error glow, message below
/// - success — green edge and a check badge (opt-in via [showSuccess])
/// - disabled — dimmed, shadowless, and rejects focus and taps entirely
///
/// Security: [onChanged] never emits control characters or zero-width joiners
/// (see [sanitize]) so invisible payloads cannot reach Firestore documents.
/// Validators must stay pure — they are re-run on every keystroke to decide the
/// success state.
class StandardInputField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? helperText;

  /// Server-side error. Wins over the [Form]'s own validation state so a failed
  /// request can highlight a field the local rules accepted.
  final String? errorText;

  final IconData? prefixIcon;
  final String? prefixText;
  final Widget? prefix;

  final Widget? suffix;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;

  /// Accessible name for the [suffixIcon] button. Required in practice: the
  /// icon carries no text, so without this a screen reader announces
  /// "button" and nothing else.
  final String? suffixTooltip;

  /// Renders the visibility toggle automatically for password intents.
  final bool showPasswordToggle;

  /// Renders a clear button once the field has content.
  final bool clearable;

  final DsKeyboard keyboard;
  final TextInputType? keyboardType;
  final TextCapitalization? textCapitalization;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool? autocorrect;
  final bool? enableSuggestions;

  final String? Function(String?)? validator;

  /// Runs [validator] on every keystroke so the error clears while typing.
  /// A parent [Form] using `autovalidateMode` already does this.
  final bool validateOnChange;

  /// Validates when the field loses focus, so a field left empty is flagged
  /// before the user reaches the submit button.
  final bool validateOnBlur;

  final ValueChanged<String>? onChanged;
  final void Function(String value)? onSubmitted;
  final VoidCallback? onTap;

  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final bool showCounter;
  final TextAlign textAlign;

  /// Overrides the "obscured" default implied by [keyboard].
  final bool? obscureText;

  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool dismissOnTapOutside;
  final EdgeInsets scrollPadding;

  /// Turns on the green edge and check badge once the value satisfies
  /// [validator].
  final bool showSuccess;

  /// Keeps a fixed-height message slot so an appearing error does not shift the
  /// rest of the form.
  final bool reserveMessageSlot;

  final DsFieldVariant variant;
  final DsFieldSize size;
  final double? radius;
  final String? semanticLabel;

  const StandardInputField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.prefixText,
    this.prefix,
    this.suffix,
    this.suffixIcon,
    this.onSuffixTap,
    this.suffixTooltip,
    this.showPasswordToggle = true,
    this.clearable = false,
    this.keyboard = DsKeyboard.text,
    this.keyboardType,
    this.textCapitalization,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.autocorrect,
    this.enableSuggestions,
    this.validator,
    this.validateOnChange = false,
    this.validateOnBlur = false,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.maxLength,
    this.minLines,
    this.maxLines,
    this.showCounter = false,
    this.textAlign = TextAlign.start,
    this.obscureText,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.dismissOnTapOutside = true,
    this.scrollPadding = const EdgeInsets.only(bottom: 24),
    this.showSuccess = false,
    this.reserveMessageSlot = true,
    this.variant = DsFieldVariant.soft,
    this.size = DsFieldSize.md,
    this.radius,
    this.semanticLabel,
  });

  /// Strips control characters and zero-width joiners that could be used to
  /// inject invisible data into Firestore documents.
  static String sanitize(String value) {
    return value
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .replaceAll('\u200B', '')
        .replaceAll('\u200C', '')
        .replaceAll('\u200D', '')
        .replaceAll('\uFEFF', '');
  }

  @override
  State<StandardInputField> createState() => _StandardInputFieldState();
}

class _StandardInputFieldState extends State<StandardInputField> {
  late FocusNode _focus = widget.focusNode ?? FocusNode();
  late bool _obscured = _resolveObscured();

  TextEditingController? _internalController;

  /// Cached so the clear button can re-sync the [FormField] after mutating the
  /// controller outside the keyboard's `onChanged` path.
  FormFieldState<String>? _formField;

  TextEditingController get _controller =>
      widget.controller ?? _internalController!;

  bool _resolveObscured() =>
      widget.obscureText ?? (widget.keyboard == DsKeyboard.password);

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController();
    }
    // Focus is not FormField state, so nothing would rebuild the chrome on
    // focus/blur — the field would stay painted as idle while being edited.
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(StandardInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focus.removeListener(_onFocusChanged);
      _focus = widget.focusNode ?? FocusNode();
      _focus.addListener(_onFocusChanged);
    }
    // An explicit `obscureText` change from the parent wins over whatever the
    // user toggled, otherwise a screen-driven reset would be ignored.
    if (oldWidget.obscureText != widget.obscureText ||
        oldWidget.keyboard != widget.keyboard) {
      _obscured = _resolveObscured();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focus.dispose();
    _internalController?.dispose();
    super.dispose();
  }

  // ── Metrics ───────────────────────────────────────────────────────────────

  double get _height => switch (widget.size) {
    DsFieldSize.sm => 44,
    DsFieldSize.md => 52,
    DsFieldSize.lg => 58,
  };

  double get _fontSize => switch (widget.size) {
    DsFieldSize.sm => 14,
    DsFieldSize.md => 15,
    DsFieldSize.lg => 17,
  };

  double get _iconSize => switch (widget.size) {
    DsFieldSize.sm => 18,
    DsFieldSize.md => 20,
    DsFieldSize.lg => 22,
  };

  double get _horizontalPadding => switch (widget.size) {
    DsFieldSize.sm => AppSpacing.s3,
    DsFieldSize.md => AppSpacing.s4,
    DsFieldSize.lg => AppSpacing.s5,
  };

  /// Held inside the 12–16px band the brand spec allows so a field never
  /// out-rounds the buttons sitting beside it.
  double get _radius =>
      widget.radius ??
      switch (widget.size) {
        DsFieldSize.sm => AppRadius.md,
        DsFieldSize.md => AppRadius.md + 2,
        DsFieldSize.lg => AppRadius.lg,
      };

  _KeyboardSpec get _spec => _specFor(widget.keyboard);

  List<TextInputFormatter> get _formatters => [
    ..._spec.formatters,
    // The limit is enforced by a formatter rather than `maxLength` so the
    // field can draw its own counter without duplicating Flutter's.
    if (widget.maxLength != null)
      LengthLimitingTextInputFormatter(widget.maxLength),
    ...?widget.inputFormatters,
  ];

  static _KeyboardSpec _specFor(DsKeyboard keyboard) {
    return switch (keyboard) {
      DsKeyboard.text => const _KeyboardSpec(
        type: TextInputType.text,
        capitalization: TextCapitalization.sentences,
        autocorrect: true,
        suggestions: true,
      ),
      DsKeyboard.email => const _KeyboardSpec(
        type: TextInputType.emailAddress,
        capitalization: TextCapitalization.none,
        autocorrect: false,
        suggestions: false,
        autofillHints: [AutofillHints.email],
      ),
      DsKeyboard.phone => _KeyboardSpec(
        type: TextInputType.phone,
        capitalization: TextCapitalization.none,
        autocorrect: false,
        suggestions: false,
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
      ),
      DsKeyboard.number => _KeyboardSpec(
        type: TextInputType.number,
        capitalization: TextCapitalization.none,
        autocorrect: false,
        suggestions: false,
        formatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      DsKeyboard.decimal => _KeyboardSpec(
        type: TextInputType.numberWithOptions(decimal: true),
        capitalization: TextCapitalization.none,
        autocorrect: false,
        suggestions: false,
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      ),
      DsKeyboard.password => const _KeyboardSpec(
        type: TextInputType.text,
        capitalization: TextCapitalization.none,
        autocorrect: false,
        suggestions: false,
        autofillHints: [AutofillHints.password],
      ),
      DsKeyboard.multiline => const _KeyboardSpec(
        type: TextInputType.multiline,
        capitalization: TextCapitalization.sentences,
        autocorrect: true,
        suggestions: true,
      ),
      DsKeyboard.search => const _KeyboardSpec(
        type: TextInputType.text,
        capitalization: TextCapitalization.sentences,
        autocorrect: false,
        suggestions: false,
        action: TextInputAction.search,
      ),
    };
  }

  TextInputType get _resolvedType {
    if (widget.keyboardType != null) return widget.keyboardType!;
    // visiblePassword only once revealed — while masked the OS must not offer
    // password-saved suggestions over the dots.
    if (widget.keyboard == DsKeyboard.password) {
      return _obscured ? TextInputType.text : TextInputType.visiblePassword;
    }
    return _spec.type;
  }

  TextInputAction get _resolvedAction {
    if (widget.textInputAction != null) return widget.textInputAction!;
    if ((widget.maxLines ?? 1) > 1) return TextInputAction.newline;
    return _spec.action ?? TextInputAction.next;
  }

  bool get _multiline =>
      widget.keyboard == DsKeyboard.multiline || (widget.maxLines ?? 1) > 1;

  // ── Chrome ────────────────────────────────────────────────────────────────

  Color _accentFor(ColorScheme scheme, DsFieldStatus status) {
    if (status == DsFieldStatus.disabled) return scheme.contentMuted;
    if (status == DsFieldStatus.error) return scheme.error;
    if (status == DsFieldStatus.focused) return scheme.primary;
    if (status == DsFieldStatus.success) return scheme.brandSuccess;
    return scheme.contentSecondary;
  }

  /// Always returns exactly three shadows: [AnimatedContainer] can only tween
  /// shadow lists of equal length, so a glow that appears on focus would snap
  /// instead of animate. Slots are (shade, highlight, glow).
  List<BoxShadow> _shadows(ColorScheme scheme, DsFieldStatus status) {
    final glowColor = switch (status) {
      DsFieldStatus.focused => scheme.primary.withValues(
        alpha: glowOpacityFor(status),
      ),
      DsFieldStatus.error => scheme.error.withValues(
        alpha: glowOpacityFor(status),
      ),
      _ => Colors.transparent,
    };
    final clear = const BoxShadow(color: Colors.transparent);
    final glow = BoxShadow(color: glowColor);

    if (widget.variant != DsFieldVariant.soft ||
        status == DsFieldStatus.disabled) {
      return [clear, clear, glow];
    }

    final dual = Neu.raised(
      status == DsFieldStatus.focused ? 3.0 : 2.0,
      scheme.brightness,
    );
    return [dual[0], dual[1], glow];
  }

  /// Low enough that the glow never washes out the 15px label or value sitting
  /// on top of it.
  static double glowOpacityFor(DsFieldStatus status) =>
      status == DsFieldStatus.error ? 0.18 : 0.26;

  BoxDecoration _decoration(ColorScheme scheme, DsFieldStatus status) {
    final (Color fill, Color edge, double width) = switch (status) {
      DsFieldStatus.disabled => (scheme.surfaceSubtle, scheme.hairline, 1.0),
      DsFieldStatus.error => (Neu.base(scheme.brightness), scheme.error, 1.5),
      DsFieldStatus.focused => (
        Neu.base(scheme.brightness),
        scheme.primary,
        1.8,
      ),
      DsFieldStatus.success => (
        Neu.base(scheme.brightness),
        scheme.brandSuccess.withValues(alpha: 0.75),
        1.4,
      ),
      DsFieldStatus.idle => switch (widget.variant) {
        // Recessed fields read as pressed-in, so they take the darker inset
        // base rather than the raised one.
        DsFieldVariant.inset => (
          Neu.insetBase(scheme.brightness),
          Neu.grooveColor(scheme.brightness),
          1.0,
        ),
        _ => (Neu.base(scheme.brightness), scheme.hairline, 1.0),
      },
    };

    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(_radius),
      border: Border.all(color: edge, width: width),
      boxShadow: _shadows(scheme, status),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final spec = _spec;

    return FormField<String>(
      // Mirrors the controller so a programmatic pre-fill or autofill also
      // seeds the value the validator sees on the next Form.validate().
      initialValue: _controller.text,
      validator: widget.validator,
      enabled: widget.enabled,
      builder: (field) {
        _formField = field;

        final text = _controller.text;
        final serverError = widget.errorText;
        final error = (serverError != null && serverError.isNotEmpty)
            ? serverError
            : field.errorText;
        final hasError = error != null && error.isNotEmpty;

        // Validators are pure, so re-running one is safe — and it is the last
        // check in the chain, so a field that is empty, focused or already in
        // error never pays for it.
        final eligible =
            widget.showSuccess &&
            !hasError &&
            !_focus.hasFocus &&
            text.isNotEmpty &&
            widget.validator?.call(text) == null;

        final status = !widget.enabled
            ? DsFieldStatus.disabled
            : hasError
            ? DsFieldStatus.error
            : _focus.hasFocus
            ? DsFieldStatus.focused
            : eligible
            ? DsFieldStatus.success
            : DsFieldStatus.idle;

        return _buildField(
          context,
          scheme,
          field,
          status,
          error,
          text,
          reduced,
          spec,
        );
      },
    );
  }

  Widget _buildField(
    BuildContext context,
    ColorScheme scheme,
    FormFieldState<String> field,
    DsFieldStatus status,
    String? error,
    String text,
    bool reduced,
    _KeyboardSpec spec,
  ) {
    final accent = _accentFor(scheme, status);

    return AnimatedOpacity(
      duration: Motion.ripple,
      opacity: widget.enabled ? 1 : 0.45,
      child: Semantics(
        textField: true,
        readOnly: widget.readOnly,
        label: widget.semanticLabel ?? widget.label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null) ...[
              _label(scheme, status, accent),
              const SizedBox(height: AppSpacing.s2),
            ],
            AnimatedContainer(
              duration: reduced ? Duration.zero : Motion.ripple,
              curve: Motion.easeOutCubic,
              decoration: _decoration(scheme, status),
              child: ConstrainedBox(
                constraints: _multiline
                    ? const BoxConstraints()
                    : BoxConstraints(minHeight: _height),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _horizontalPadding,
                    vertical: _multiline ? AppSpacing.s3 : 0,
                  ),
                  child: Row(
                    crossAxisAlignment: _multiline
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      if (_leading(scheme, accent, reduced)
                          case final lead?) ...[
                        lead,
                        SizedBox(width: _horizontalPadding - 4),
                      ],
                      Expanded(child: _textField(scheme, field, spec, reduced)),
                      if (_trailing(scheme, status, text, reduced)
                          case final trail?) ...[
                        SizedBox(width: _horizontalPadding - 8),
                        trail,
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _message(scheme, status, error),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    ColorScheme scheme,
    FormFieldState<String> field,
    _KeyboardSpec spec,
    bool reduced,
  ) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      obscureText: _obscured,
      keyboardType: _resolvedType,
      textInputAction: _resolvedAction,
      textCapitalization: widget.textCapitalization ?? spec.capitalization,
      textAlign: widget.textAlign,
      textAlignVertical: _multiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      autocorrect: widget.autocorrect ?? spec.autocorrect,
      enableSuggestions: widget.enableSuggestions ?? spec.suggestions,
      autofillHints: widget.autofillHints ?? spec.autofillHints,
      inputFormatters: _formatters,
      cursorColor: scheme.primary,
      cursorWidth: 2,
      cursorRadius: const Radius.circular(2),
      scrollPadding: widget.scrollPadding,
      minLines: widget.minLines ?? 1,
      maxLines: _obscured ? 1 : (widget.maxLines ?? (_multiline ? 4 : 1)),
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: _fontSize,
        fontWeight: FontWeight.w500,
        height: 1.25,
        color: widget.enabled ? scheme.contentPrimary : scheme.contentMuted,
      ),
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: _fontSize,
          fontWeight: FontWeight.w400,
          color: scheme.contentMuted,
        ),
      ),
      onChanged: (raw) {
        final value = StandardInputField.sanitize(raw);
        // Writing the sanitized value back keeps the caret aligned with the
        // text the user can actually see after stripping.
        if (value != raw) {
          final offset = _controller.selection.baseOffset.clamp(
            0,
            value.length,
          );
          _controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: offset),
          );
        }
        field.didChange(value);
        if (widget.validateOnChange) field.validate();
        widget.onChanged?.call(value);
      },
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      onTapOutside: (event) {
        // Mouse clicks should not dismiss focus; only touch and stylus.
        if (!widget.dismissOnTapOutside) return;
        if (event.kind == PointerDeviceKind.mouse) return;
        if (widget.validateOnBlur) field.validate();
        _focus.unfocus();
      },
    );
  }

  Widget _label(ColorScheme scheme, DsFieldStatus status, Color accent) {
    return AnimatedDefaultTextStyle(
      duration: Motion.ripple,
      curve: Motion.easeOutCubic,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: status == DsFieldStatus.idle || status == DsFieldStatus.disabled
            ? scheme.contentSecondary
            : accent,
      ),
      child: Text(widget.label!, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// A custom `prefix` overrides the icon/text shorthand, so a screen can drop
  /// an avatar or a country flag in without giving up the field's chrome.
  Widget? _leading(ColorScheme scheme, Color accent, bool reduced) {
    if (widget.prefix != null) return widget.prefix;

    final children = <Widget>[];
    if (widget.prefixIcon != null) {
      children.add(
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: accent),
          duration: reduced ? Duration.zero : Motion.ripple,
          builder: (context, color, _) =>
              Icon(widget.prefixIcon, size: _iconSize, color: color),
        ),
      );
    }
    if (widget.prefixText != null) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        Text(
          widget.prefixText!,
          style: AppTypography.monoLabel(
            scheme.contentSecondary,
          ).copyWith(fontSize: 14),
        ),
      );
      children.add(
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.only(left: AppSpacing.s3),
          color: scheme.hairline,
        ),
      );
    }
    if (children.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// Slots keep a stable position across states so a success badge replacing
  /// nothing and a clear button appearing animate instead of the whole row
  /// re-laying out.
  Widget? _trailing(
    ColorScheme scheme,
    DsFieldStatus status,
    String text,
    bool reduced,
  ) {
    if (widget.suffix != null) return widget.suffix;

    final items = <Widget>[];

    if (widget.showPasswordToggle && widget.keyboard == DsKeyboard.password) {
      items.add(
        _iconButton(
          key: const ValueKey('password_toggle'),
          icon: _obscured
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          tooltip: _obscured ? 'Hide password' : 'Show password',
          color: scheme.contentSecondary,
          reduced: reduced,
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      );
    }

    if (status == DsFieldStatus.success) {
      items.add(_successBadge(scheme, reduced));
    }

    if (widget.clearable && text.isNotEmpty) {
      items.add(
        _iconButton(
          key: const ValueKey('clear'),
          icon: Icons.cancel_rounded,
          tooltip: 'Clear',
          color: scheme.contentMuted,
          reduced: reduced,
          onPressed: _clear,
        ),
      );
    }

    if (widget.suffixIcon != null) {
      final onTap = widget.onSuffixTap;
      items.add(
        onTap == null
            ? Icon(
                widget.suffixIcon,
                size: _iconSize,
                color: scheme.contentMuted,
              )
            : _iconButton(
                key: const ValueKey('suffix'),
                icon: widget.suffixIcon!,
                tooltip: widget.suffixTooltip,
                color: scheme.contentSecondary,
                reduced: reduced,
                onPressed: onTap,
              ),
      );
    }

    if (widget.showCounter && widget.maxLength != null) {
      items.add(
        Text(
          '${text.length}/${widget.maxLength}',
          style: AppTypography.timeIndicator(scheme.contentMuted),
        ),
      );
    }

    if (items.isEmpty) return null;

    final spaced = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: AppSpacing.s1));
      spaced.add(items[i]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: spaced);
  }

  void _clear() {
    _controller.clear();
    // The controller was mutated outside `onChanged`, so push the empty value
    // through the same FormField path the keyboard uses.
    _formField?.didChange('');
    _formField?.validate();
    widget.onChanged?.call('');
    _focus.requestFocus();
  }

  Widget _iconButton({
    required Key key,
    required IconData icon,
    required String? tooltip,
    required Color color,
    required bool reduced,
    required VoidCallback onPressed,
  }) {
    final button = IconButton(
      icon: Icon(icon, size: _iconSize - 2),
      color: color,
      onPressed: widget.enabled ? onPressed : null,
      padding: EdgeInsets.zero,
      splashRadius: _iconSize,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : Motion.ripple,
      switchInCurve: Motion.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: key,
        child: Semantics(
          button: true,
          label: tooltip,
          child: tooltip == null
              ? button
              : Tooltip(message: tooltip, child: button),
        ),
      ),
    );
  }

  Widget _successBadge(ColorScheme scheme, bool reduced) {
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
      switchInCurve: Motion.overshootSpring,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        key: const ValueKey('success'),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: scheme.brandSuccess.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, size: 14, color: scheme.brandSuccess),
      ),
    );
  }

  /// An error message replaces the helper text in the same slot; the slot keeps
  /// its height reserved so revealing an error never reflows the form.
  Widget _message(ColorScheme scheme, DsFieldStatus status, String? error) {
    final isError = status == DsFieldStatus.error;
    final resolved = isError
        ? error
        : (status == DsFieldStatus.disabled ? null : widget.helperText);
    final hasMessage = resolved != null && resolved.isNotEmpty;

    return AnimatedSize(
      duration: Motion.ripple,
      curve: Motion.easeOutCubic,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: double.infinity,
        child: hasMessage
            ? Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s2, left: 2),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    resolved,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: isError ? FontWeight.w500 : FontWeight.w400,
                      height: 1.3,
                      color: isError ? scheme.error : scheme.contentMuted,
                    ),
                  ),
                ),
              )
            : SizedBox(height: widget.reserveMessageSlot ? 16 : 0),
      ),
    );
  }
}
