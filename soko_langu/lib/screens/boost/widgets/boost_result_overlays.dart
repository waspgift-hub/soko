import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../extensions/context_tr.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/ds/ds.dart';
import '../boost_tiers.dart';

/// Waiting state while the collection webhook settles the payment.
///
/// Blocks the screen on purpose: USSD needs the seller to act on their handset
/// right now, and letting them tap around a half-finished payment is how
/// double charges happen.
class BoostProgressOverlay extends StatefulWidget {
  final BoostTier tier;

  const BoostProgressOverlay({super.key, required this.tier});

  @override
  State<BoostProgressOverlay> createState() => _BoostProgressOverlayState();
}

class _BoostProgressOverlayState extends State<BoostProgressOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  int _step = 0;

  static const List<Duration> _stepDelays = [Duration(milliseconds: 900), Duration(seconds: 5)];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);

    for (final delay in _stepDelays) {
      Future.delayed(delay, () {
        if (!mounted) return;
        setState(() => _step = (_step + 1).clamp(0, 2));
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.tr('boost_step_request'),
      context.tr('boost_step_approve'),
      context.tr('boost_step_confirm'),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xF2050706),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => Container(
                      width: 108 + _pulse.value * 14,
                      height: 108 + _pulse.value * 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tierColor.withValues(alpha: 0.10 + _pulse.value * 0.10),
                      ),
                      child: Center(
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tierColor.withValues(alpha: 0.16),
                            border: Border.all(color: tierColor.withValues(alpha: 0.5), width: 1.5),
                          ),
                          child: Icon(Icons.sms_rounded, size: 36, color: tierColor),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s6),
                Text(
                  context.tr('boost_processing'),
                  textAlign: TextAlign.center,
                  style: AppTypography.screenTitle(Colors.white).copyWith(fontSize: 22),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  context.trParams('boost_processing_body', {
                    'amount': context.formatPriceInt(widget.tier.price, currencyOverride: 'TZS'),
                  }),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.s7),
                DsPaymentStatusTimeline(step: _step, labels: labels, color: tierColor),
                const SizedBox(height: AppSpacing.s2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final label in labels)
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s7),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          context.tr('boost_please_wait'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s5),
                DsButton(
                  label: context.tr('boost_check_later'),
                  variant: DsButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color get tierColor => const Color(0xFF00C853);
}

/// BillPay hand-off: the seller gets a control number and pays it from their own
/// wallet app, so this screen's only job is to make that number impossible to
/// mistype.
class BoostBillPaySheet extends StatelessWidget {
  const BoostBillPaySheet({super.key, required this.controlNumber, required this.tier});

  final String controlNumber;
  final BoostTier tier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DsSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.receipt_long_rounded, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  context.tr('boost_receipt_title'),
                  style: AppTypography.screenTitle(scheme.onSurface).copyWith(fontSize: 19),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            context.tr('boost_billpay_number_label'),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.s2),
          _CopyableControlNumber(number: controlNumber),
          const SizedBox(height: AppSpacing.s4),
          Text(
            context.trParams('boost_billpay_instructions', {
              'amount': context.formatPriceInt(tier.price, currencyOverride: 'TZS'),
            }),
            style: TextStyle(color: scheme.onSurface, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.s5),
          DsButton(
            label: context.tr('boost_done'),
            size: DsButtonSize.lg,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _CopyableControlNumber extends StatelessWidget {
  const _CopyableControlNumber({required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedPress(
      pressedScale: 0.98,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: number));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('boost_copied'))));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4, vertical: AppSpacing.s3),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                number,
                style: AppTypography.amount(
                  scheme.onSurface,
                ).copyWith(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 3),
              ),
            ),
            Icon(Icons.copy_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// Post-payment confirmation. Only reachable once the server has committed the
/// boost batch, so it is safe to celebrate here.
class BoostSuccessOverlay extends StatelessWidget {
  const BoostSuccessOverlay({super.key, required this.productName, required this.tier});

  final String productName;
  final BoostTier tier;

  @override
  Widget build(BuildContext context) {
    CelebrationOverlay.show(context);

    return Scaffold(
      backgroundColor: const Color(0xF2050706),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: _SuccessRing()),
              const SizedBox(height: AppSpacing.s6),
              Text(
                context.tr('boost_complete'),
                textAlign: TextAlign.center,
                style: AppTypography.screenTitle(Colors.white).copyWith(fontSize: 26),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                context.tr('boost_confirmed_body'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.s7),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius2.xl),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Column(
                  children: [
                    _SummaryRow(label: context.tr('product'), value: productName),
                    _SummaryRow(
                      label: context.tr('boost_tier_label'),
                      value: context.tr('boost_tier_${tier.key}'),
                    ),
                    _SummaryRow(
                      label: context.tr('boost_package_title'),
                      value: context.trParams('boost_days', {'count': '${tier.days}'}),
                    ),
                    DsDivider(color: Colors.white.withValues(alpha: 0.12)),
                    _SummaryRow(
                      label: context.tr('total'),
                      value: context.formatPriceInt(tier.price, currencyOverride: 'TZS'),
                      highlight: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s6),
              DsButton(
                label: context.tr('boost_view_my_boosts'),
                icon: Icons.campaign_rounded,
                size: DsButtonSize.lg,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(AppRoutes.myAds);
                },
              ),
              const SizedBox(height: AppSpacing.s3),
              DsButton(
                label: context.tr('boost_done'),
                variant: DsButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessRing extends StatefulWidget {
  const _SuccessRing();

  @override
  State<_SuccessRing> createState() => _SuccessRingState();
}

class _SuccessRingState extends State<_SuccessRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const _RingBody(progress: 1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _RingBody(progress: _controller.value),
    );
  }
}

class _RingBody extends StatelessWidget {
  const _RingBody({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final pop = Motion.overshootSpring.transform((progress - 0.35).clamp(0.0, 1.0) / 0.65);
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF00C853).withValues(alpha: 0.14),
        border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.55), width: 2),
      ),
      child: Center(
        child: Transform.scale(
          scale: 0.5 + pop * 0.5,
          child: Container(
            width: 66,
            height: 66,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00C853)),
            child: const Icon(Icons.check_rounded, size: 40, color: Colors.black),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12.5),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: highlight ? 17 : 13.5,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
