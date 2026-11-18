import 'package:flutter/material.dart';

import '../extensions/context_tr.dart';

/// Discrete trust vote collected on a seller profile.
enum SellerTrustVote {
  trustworthy,
  notTrustworthy;

  /// Rating value stored by [RatingService]; the profile trust score is the
  /// average of these votes, so the two options are the 5/1 endpoints.
  int get rating => this == SellerTrustVote.trustworthy ? 5 : 1;
}

/// Bottom sheet that replaces the old `AlertDialog` + two `ElevatedButton`s.
///
/// The dialog put a long Swahili label inside a fixed-width button pair, which
/// overflowed at large font scales and read like a destructive confirmation.
/// A sheet gives each option a full-width row with an explanation, works with
/// the keyboard/viewInsets, and is scrollable so it can never overflow.
class RateSellerSheet extends StatefulWidget {
  const RateSellerSheet({super.key, required this.sellerName});

  final String sellerName;

  /// Returns the chosen vote, or null when dismissed.
  static Future<SellerTrustVote?> show(
    BuildContext context, {
    required String sellerName,
  }) {
    return showModalBottomSheet<SellerTrustVote>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RateSellerSheet(sellerName: sellerName),
    );
  }

  @override
  State<RateSellerSheet> createState() => _RateSellerSheetState();
}

class _RateSellerSheetState extends State<RateSellerSheet> {
  SellerTrustVote? _selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = widget.sellerName.trim();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  context.tr('rate_seller'),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name.isEmpty
                      ? context.tr('rate_seller_trust_prompt')
                      : context.tr('rate_seller_named', 'How was your experience with {name}?')
                          .replaceAll('{name}', name),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                _VoteCard(
                  icon: Icons.thumb_up_alt_rounded,
                  title: context.tr('trustworthy'),
                  subtitle: context.tr(
                    'trustworthy_hint',
                    'Item matched the listing and the seller communicated well.',
                  ),
                  accent: cs.primary,
                  selected: _selected == SellerTrustVote.trustworthy,
                  onTap: () => setState(() => _selected = SellerTrustVote.trustworthy),
                ),
                const SizedBox(height: 10),
                _VoteCard(
                  icon: Icons.thumb_down_alt_rounded,
                  title: context.tr('not_trustworthy'),
                  subtitle: context.tr(
                    'not_trustworthy_hint',
                    'Misleading listing, no delivery, or a bad experience.',
                  ),
                  accent: cs.error,
                  selected: _selected == SellerTrustVote.notTrustworthy,
                  onTap: () => setState(() => _selected = SellerTrustVote.notTrustworthy),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: _selected == SellerTrustVote.notTrustworthy
                        ? cs.error
                        : cs.primary,
                    foregroundColor: _selected == SellerTrustVote.notTrustworthy
                        ? cs.onError
                        : cs.onPrimary,
                  ),
                  child: Text(
                    context.tr('submit_rating', 'Submit rating'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoteCard extends StatelessWidget {
  const _VoteCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.10)
                : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent : cs.outlineVariant.withValues(alpha: 0.5),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.18)
                      : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? accent : cs.outlineVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
