import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../extensions/context_tr.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_motion.dart';
import '../../../widgets/ds/ds.dart';
import '../boost_tiers.dart';

enum BoostPayMethod { ussd, billpay }

/// Phone number, operator and payment rail, collapsed behind one card.
///
/// The operator logos are the highest-trust signal in Tanzanian mobile money,
/// so they are drawn from the operators' own brand colours rather than the
/// generic chip styling used everywhere else in the app.
class BoostPaymentSection extends StatelessWidget {
  const BoostPaymentSection({
    super.key,
    required this.phoneController,
    required this.method,
    required this.provider,
    required this.onMethodChanged,
    required this.onProviderChanged,
    required this.phoneError,
  });

  final TextEditingController phoneController;
  final BoostPayMethod method;
  final String provider;
  final ValueChanged<BoostPayMethod> onMethodChanged;
  final ValueChanged<String> onProviderChanged;
  final String? phoneError;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            icon: Icons.payments_rounded,
            title: context.tr('boost_section_payment'),
            subtitle: context.tr('boost_payment_subtitle'),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            context.tr('boost_phone_label'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
              LengthLimitingTextInputFormatter(16),
            ],
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.4),
            decoration: InputDecoration(
              hintText: context.tr('boost_phone_hint'),
              errorText: phoneError,
              prefixIcon: const Icon(Icons.smartphone_rounded, size: 20),
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
          Text(
            context.tr('boost_provider_label'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: boostProviders.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s2),
              itemBuilder: (context, i) {
                final (key, label, brand) = boostProviders[i];
                return _ProviderTile(
                  label: label,
                  brand: brand,
                  selected: provider == key,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onProviderChanged(key);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
          Text(
            context.tr('boost_method_label'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _MethodToggle(
            method: method,
            onChanged: (next) {
              HapticFeedback.selectionClick();
              onMethodChanged(next);
            },
          ),
          const SizedBox(height: AppSpacing.s3),
          AnimatedSwitcher(
            duration: Motion.cardEnter,
            child: Text(
              context.tr(
                method == BoostPayMethod.ussd
                    ? 'boost_method_ussd_help'
                    : 'boost_method_billpay_help',
              ),
              key: ValueKey(method),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.label,
    required this.brand,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color brand;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedPress(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: Motion.cardPress,
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        decoration: BoxDecoration(
          color: selected
              ? brand.withValues(alpha: 0.10)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? brand : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: brand,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Text(
                label.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  const _MethodToggle({required this.method, required this.onChanged});

  final BoostPayMethod method;
  final ValueChanged<BoostPayMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          _Segment(
            label: context.tr('boost_method_ussd_short'),
            icon: Icons.smartphone_rounded,
            selected: method == BoostPayMethod.ussd,
            onTap: () => onChanged(BoostPayMethod.ussd),
          ),
          _Segment(
            label: context.tr('boost_method_billpay_short'),
            icon: Icons.receipt_long_rounded,
            selected: method == BoostPayMethod.billpay,
            onTap: () => onChanged(BoostPayMethod.billpay),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: AnimatedPress(
        onTap: onTap,
        pressedScale: 0.98,
        child: AnimatedContainer(
          duration: Motion.cardPress,
          height: 42,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
