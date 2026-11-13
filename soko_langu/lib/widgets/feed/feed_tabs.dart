import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';

/// Social feed selector: For You / Nearby / Trending.
/// The selected tab is filled; others are outlined chips.
enum FeedTab { forYou, nearby, trending }

class FeedTabs extends StatelessWidget {
  final FeedTab selected;
  final ValueChanged<FeedTab> onSelect;

  const FeedTabs({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  String _label(BuildContext context, FeedTab t) {
    switch (t) {
      case FeedTab.forYou:
        return context.tr('for_you', 'For You');
      case FeedTab.nearby:
        return context.tr('nearby', 'Nearby');
      case FeedTab.trending:
        return context.tr('trending', 'Trending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Precise sticky header spacing — 16 horizontal, 10 vertical for breathing
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: FeedTab.values.map((t) {
          final active = t == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(_label(context, t), style: TextStyle(fontSize: 13, letterSpacing: 0.1)),
              ),
              selected: active,
              onSelected: (_) => onSelect(t),
              selectedColor: cs.primary,
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              side: BorderSide(color: active ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              labelStyle: TextStyle(
                color: active ? cs.onPrimary : cs.onSurface,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          );
        }).toList(),
      ),
    );
  }
}
