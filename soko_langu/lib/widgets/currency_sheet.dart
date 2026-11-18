import 'package:flutter/material.dart';

import '../main.dart';
import '../services/localization_service.dart';
import '../extensions/context_tr.dart';

/// Shared currency picker used by Home, Discovery and Settings.
///
/// Replaces three near-identical `showModalBottomSheet` copies that rendered a
/// bare `Column(mainAxisSize: min)` — nine currency rows plus padding is
/// ~560 dp, which is what produced "BOTTOM OVERFLOWED BY 179 PIXELS" on short
/// devices. A [DraggableScrollableSheet] sizes itself to the viewport and the
/// list scrolls with the sheet's own controller, so the content can never
/// exceed the available height regardless of row count, font scale or keyboard.
class CurrencySheet extends StatefulWidget {
  const CurrencySheet({super.key, required this.scrollController});

  final ScrollController scrollController;

  /// Presents the picker and applies the selection. Resolves when the sheet is
  /// dismissed.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.38,
        maxChildSize: 0.92,
        snap: true,
        snapSizes: const [0.62, 0.92],
        builder: (_, controller) => CurrencySheet(scrollController: controller),
      ),
    );
  }

  @override
  State<CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<CurrencySheet> {
  late final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = AppConfig.of(context);

    final entries = LocalizationService.supportedCurrencies.entries.where((e) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.key.toLowerCase().contains(q) ||
          e.value['name']!.toLowerCase().contains(q) ||
          e.value['symbol']!.toLowerCase().contains(q);
    }).toList();

    return Material(
      color: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payments_outlined, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('select_currency'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr(
                          'currency_sheet_subtitle',
                          'Prices across the app are shown in this currency.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: context.tr('search_currency', 'Search currency'),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      context.tr('no_results', 'No match found'),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    controller: widget.scrollController,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      MediaQuery.paddingOf(context).bottom + 16,
                    ),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      final selected = config.currencyCode == e.key;
                      return _CurrencyTile(
                        code: e.key,
                        name: e.value['name'] ?? e.key,
                        symbol: e.value['symbol'] ?? e.key,
                        selected: selected,
                        onTap: () {
                          LocalizationService().setCurrency(e.key);
                          config.onSetCurrency(e.key);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile({
    required this.code,
    required this.name,
    required this.symbol,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final String symbol;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  symbol,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: symbol.length > 1 ? 11 : 16,
                    fontWeight: FontWeight.w800,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      code,
                      style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.3,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: selected
                    ? Icon(Icons.check_circle_rounded,
                        key: const ValueKey('on'), color: cs.primary, size: 22)
                    : Icon(Icons.circle_outlined,
                        key: const ValueKey('off'),
                        color: cs.outlineVariant,
                        size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
