import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Phone input with a static Tanzania (+255) prefix.
///
/// No country selector — Tanzania is the only supported market.
/// The parent normalizes via [PhoneUtils.toE164] which assumes dial 255.
class AuthPhoneField extends StatefulWidget {
  final TextEditingController controller;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const AuthPhoneField({
    super.key,
    required this.controller,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  State<AuthPhoneField> createState() => AuthPhoneFieldState();
}

class AuthPhoneFieldState extends State<AuthPhoneField> {
  late final FocusNode _focus = FocusNode();
  late final ValueNotifier<bool> _focused = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    _focused.value = _focus.hasFocus;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _focused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: _focused,
      builder: (context, focused, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: focused ? cs.primary : cs.brandBorder,
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🇹🇿', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      '+255',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: focused ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 34,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: cs.brandBorder,
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.phone,
                  textInputAction: widget.textInputAction,
                  onFieldSubmitted: widget.onFieldSubmitted,
                  validator: widget.validator,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    hintText: '0XXXXXXXXX',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    errorStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        );
      },
    );
  }
}
