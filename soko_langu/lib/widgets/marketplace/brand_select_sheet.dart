import 'package:flutter/material.dart';
import '../../data/marketplace_taxonomy.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/inputs/soko_search_bar.dart';

/// Opens the multi-select brand picker. Returns the picked brand names,
/// or null when dismissed without applying.
Future<Set<String>?> showBrandSelectSheet(
  BuildContext context, {
  required List<TaxonomyBrand> brands,
  required Set<String> selected,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => BrandSelectSheet(brands: brands, selected: selected),
  );
}

/// Brand multi-select with search, clear, and apply. Brands render as
/// neutral initial-avatars because logo reuse is a licensing risk.
class BrandSelectSheet extends StatefulWidget {
  final List<TaxonomyBrand> brands;
  final Set<String> selected;
  const BrandSelectSheet({
    super.key,
    required this.brands,
    required this.selected,
  });

  @override
  State<BrandSelectSheet> createState() => _BrandSelectSheetState();
}

class _BrandSelectSheetState extends State<BrandSelectSheet> {
  late Set<String> _sel;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _sel = Set.of(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.brands
        : widget.brands
            .where((b) => b.name.toLowerCase().contains(q))
            .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('brand'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (_sel.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_sel.clear),
                      child: Text(
                        context.tr('clear_all'),
                        style: TextStyle(color: cs.primary),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: SokoSearchBar(
                hint: context.tr('search_brands'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.tr('no_brands_found'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final b = shown[i];
                        final on = _sel.contains(b.name);
                        return CheckboxListTile(
                          value: on,
                          onChanged: (_) => setState(() {
                            on ? _sel.remove(b.name) : _sel.add(b.name);
                          }),
                          controlAffinity: ListTileControlAffinity.trailing,
                          secondary: CircleAvatar(
                            backgroundColor: on
                                ? cs.primary
                                : cs.primaryContainer,
                            child: Text(
                              b.name.isEmpty ? '?' : b.name[0].toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: on
                                    ? cs.onPrimary
                                    : cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                          title: Text(
                            b.name,
                            style: TextStyle(
                              fontWeight:
                                  on ? FontWeight.w700 : FontWeight.w500,
                              color: cs.onSurface,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_sel),
                  child: Text(
                    _sel.isEmpty
                        ? context.tr('apply')
                        : '${context.tr('apply')} (${_sel.length})',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
