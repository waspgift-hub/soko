import 'package:flutter/material.dart';
import '../../theme/app_dimens.dart';

/// Social feed selector: For You / Following / Nearby / Trending.
/// The selected tab is filled; others are outlined chips.
enum FeedTab { forYou, following, nearby, trending }

const feedTabLabels = {
  FeedTab.forYou: 'For You',
  FeedTab.following: 'Following',
  FeedTab.nearby: 'Nearby',
  FeedTab.trending: 'Trending',
};

class FeedTabs extends StatelessWidget {
  final FeedTab selected;
  final ValueChanged<FeedTab> onSelect;

  const FeedTabs({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      child: Row(
        children: FeedTab.values.map((t) {
          final active = t == selected;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s2),
            child: ChoiceChip(
              label: Text(feedTabLabels[t]!),
              selected: active,
              onSelected: (_) => onSelect(t),
              selectedColor: cs.primary,
              labelStyle: TextStyle(
                color: active ? cs.onPrimary : cs.onSurface,
                fontWeight:
                    active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
