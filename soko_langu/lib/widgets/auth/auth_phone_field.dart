import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'auth_countries.dart';

/// Phone input with an inline country-code selector.
///
/// Renders a tappable `+255` chip next to the number field; tapping the chip
/// opens a searchable country bottom sheet. The selected country is exposed
/// via [AuthPhoneFieldState.selectedCountry] so the parent can normalize the
/// number against the correct dial code.
class AuthPhoneField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<AuthCountry>? onCountryChanged;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const AuthPhoneField({
    super.key,
    required this.controller,
    this.onCountryChanged,
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
  AuthCountry _country = kAuthCountries.first;

  AuthCountry get selectedCountry => _country;

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

  Future<void> _selectCountry() async {
    final cs = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<AuthCountry>(
      context: context,
      backgroundColor: cs.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CountryPicker(
        countries: kAuthCountries,
        current: _country,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _country = selected);
      widget.onCountryChanged?.call(selected);
      HapticFeedback.selectionClick();
    }
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
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _selectCountry,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.lg),
                    bottomLeft: Radius.circular(AppRadius.lg),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_country.flag, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 6),
                        Text(
                          _country.displayDial,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: focused ? cs.primary : cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.expand_more,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
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

class _CountryPicker extends StatelessWidget {
  final List<AuthCountry> countries;
  final AuthCountry current;

  const _CountryPicker({
    required this.countries,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController();
    return StatefulBuilder(
      builder: (context, setSheetState) {
        final query = controller.text.trim().toLowerCase();
        final filtered = countries
            .where((c) =>
                query.isEmpty ||
                c.name.toLowerCase().contains(query) ||
                c.dial.contains(query))
            .toList();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: TextField(
                      controller: controller,
                      onChanged: (_) => setSheetState(() {}),
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: context.tr('country_search_hint'),
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        final selected = c.dial == current.dial;
                        return ListTile(
                          leading: Text(c.flag, style: const TextStyle(fontSize: 20)),
                          title: Text(
                            c.name,
                            style: TextStyle(
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          trailing: selected
                              ? Icon(Icons.check_circle, color: cs.primary)
                              : Text(
                                  c.displayDial,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}