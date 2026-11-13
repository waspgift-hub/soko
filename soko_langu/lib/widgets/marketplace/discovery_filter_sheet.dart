import 'package:flutter/material.dart';
import '../../data/marketplace_taxonomy.dart';
import '../../extensions/context_tr.dart';
import '../../main.dart';
import '../../models/discovery_filters.dart';
import 'brand_select_sheet.dart';

/// Opens the category-aware filter sheet. Returns the applied filter,
/// or null when dismissed.
Future<ProductFilter?> showDiscoveryFilterSheet(
  BuildContext context, {
  required TaxonomyCategory? taxonomy,
  required ProductFilter initial,
  required int Function(ProductFilter) countResults,
}) {
  return showModalBottomSheet<ProductFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DiscoveryFilterSheet(
      taxonomy: taxonomy,
      initial: initial,
      countResults: countResults,
    ),
  );
}

class _DiscoveryFilterSheet extends StatefulWidget {
  final TaxonomyCategory? taxonomy;
  final ProductFilter initial;
  final int Function(ProductFilter) countResults;
  const _DiscoveryFilterSheet({
    required this.taxonomy,
    required this.initial,
    required this.countResults,
  });

  @override
  State<_DiscoveryFilterSheet> createState() => _DiscoveryFilterSheetState();
}

class _DiscoveryFilterSheetState extends State<_DiscoveryFilterSheet> {
  late ProductFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = AppConfig.of(context).langCode;
    final count = widget.countResults(_draft);
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
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
                      context.tr('filters'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _draft = const ProductFilter(),
                    ),
                    child: Text(
                      context.tr('clear_all'),
                      style: TextStyle(color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: cs.outlineVariant),
            Expanded(
              child: DiscoveryFilterBody(
                taxonomy: widget.taxonomy,
                value: _draft,
                onChanged: (f) => setState(() => _draft = f),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: Text(
                    _draft.isEmpty
                        ? context.tr('reset')
                        : _showResultsText(lang, count),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _showResultsText(String lang, int count) {
    final t = _trParams('show_x_results', lang, {'0': '$count'});
    return t;
  }

  String _trParams(String key, String lang, Map<String, String> params) {
    // Mirrors LocalizationService.trParams without importing the service.
    var text = context.tr(key);
    params.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return text;
  }
}

/// Category-aware filter controls, shared by the bottom sheet and the
/// desktop sidebar so both surfaces stay identical.
class DiscoveryFilterBody extends StatefulWidget {
  final TaxonomyCategory? taxonomy;
  final ProductFilter value;
  final ValueChanged<ProductFilter> onChanged;
  const DiscoveryFilterBody({
    super.key,
    required this.taxonomy,
    required this.value,
    required this.onChanged,
  });

  @override
  State<DiscoveryFilterBody> createState() => _DiscoveryFilterBodyState();
}

class _DiscoveryFilterBodyState extends State<DiscoveryFilterBody> {
  late TextEditingController _minCtrl;
  late TextEditingController _maxCtrl;
  late TextEditingController _locCtrl;

  @override
  void initState() {
    super.initState();
    _minCtrl = TextEditingController(
      text: widget.value.minPrice?.toStringAsFixed(0) ?? '',
    );
    _maxCtrl = TextEditingController(
      text: widget.value.maxPrice?.toStringAsFixed(0) ?? '',
    );
    _locCtrl = TextEditingController(text: widget.value.location);
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  void _emit(ProductFilter f) => widget.onChanged(f);

  @override
  Widget build(BuildContext context) {
    final tax = widget.taxonomy;
    final f = widget.value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _sortSection(f),
        if (tax != null && tax.popularFilters.isNotEmpty)
          _flagSection(context.tr('popular_filters'), tax.popularFilters, f),
        if (tax != null && tax.brands.isNotEmpty) _brandSection(tax, f),
        _priceSection(f),
        _conditionSection(f),
        _locationSection(f),
        if (tax != null)
          for (final spec in tax.filters)
            if (spec.options.isNotEmpty) _optionsSection(spec, f),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _sortSection(ProductFilter f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.tr('sort_by')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _singleChip('newest', context.tr('new'), f.sort),
            _singleChip(
              'price_asc',
              context.tr('price_low_to_high'),
              f.sort,
            ),
            _singleChip(
              'price_desc',
              context.tr('price_high_to_low'),
              f.sort,
            ),
            _singleChip('popular', context.tr('popular'), f.sort),
          ],
        ),
      ],
    );
  }

  Widget _singleChip(String value, String label, String group) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: group == value,
      onSelected: (_) => _emit(widget.value.copyWith(sort: value)),
    );
  }

  Widget _flagSection(String title, List<String> keys, ProductFilter f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in keys)
              Builder(builder: (context) {
                final def = popularFlagByKey(key);
                if (def == null) return const SizedBox.shrink();
                final label = def.label ??
                    (def.labelKey != null
                        ? context.tr(def.labelKey!)
                        : key);
                final on = f.flags.contains(key);
                return FilterChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: on,
                  onSelected: (_) {
                    final next = Set<String>.of(f.flags);
                    on ? next.remove(key) : next.add(key);
                    _emit(widget.value.copyWith(flags: next));
                  },
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _brandSection(TaxonomyCategory tax, ProductFilter f) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.tr('brand')),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showBrandSelectSheet(
              context,
              brands: tax.brands,
              selected: f.brands,
            );
            if (picked != null && mounted) {
              _emit(widget.value.copyWith(brands: picked));
            }
          },
          icon: const Icon(Icons.style_rounded, size: 18),
          label: Text(
            f.brands.isEmpty
                ? context.tr('all')
                : f.brands.join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (f.brands.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final b in f.brands)
                Chip(
                  label: Text(b, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () {
                    final next = Set<String>.of(f.brands)..remove(b);
                    _emit(widget.value.copyWith(brands: next));
                  },
                  backgroundColor: cs.primaryContainer,
                  labelStyle: TextStyle(color: cs.onPrimaryContainer),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _priceSection(ProductFilter f) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.tr('price')),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minCtrl,
                keyboardType: TextInputType.number,
                decoration: _numDecoration(
                  cs,
                  context.tr('min_price'),
                ),
                style: TextStyle(fontSize: 14, color: cs.onSurface),
                onChanged: (v) => _emit(
                  widget.value.copyWith(minPrice: double.tryParse(v)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '-',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _maxCtrl,
                keyboardType: TextInputType.number,
                decoration: _numDecoration(
                  cs,
                  context.tr('max_price'),
                ),
                style: TextStyle(fontSize: 14, color: cs.onSurface),
                onChanged: (v) => _emit(
                  widget.value.copyWith(maxPrice: double.tryParse(v)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _numDecoration(ColorScheme cs, String hint) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.outlineVariant),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      border: border,
      enabledBorder: border,
    );
  }

  Widget _conditionSection(ProductFilter f) {
    const values = ['all', 'new', 'used', 'refurbished'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.tr('condition')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(
                  context.tr(v),
                  style: const TextStyle(fontSize: 12),
                ),
                selected: f.condition == v,
                onSelected: (_) =>
                    _emit(widget.value.copyWith(condition: v)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _locationSection(ProductFilter f) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.tr('location')),
        TextField(
          controller: _locCtrl,
          decoration: _numDecoration(cs, context.tr('location')),
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          onChanged: (v) =>
              _emit(widget.value.copyWith(location: v.trim())),
        ),
      ],
    );
  }

  Widget _optionsSection(TaxFilter spec, ProductFilter f) {
    final selected = f.attributes[spec.key] ?? const <String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.tr(spec.labelKey)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in spec.options)
              FilterChip(
                label: Text(o, style: const TextStyle(fontSize: 12)),
                selected: selected.contains(o),
                onSelected: (_) {
                  final next = Map<String, Set<String>>.of(f.attributes);
                  final set = Set<String>.of(selected);
                  set.contains(o) ? set.remove(o) : set.add(o);
                  next[spec.key] = set;
                  _emit(widget.value.copyWith(attributes: next));
                },
              ),
          ],
        ),
      ],
    );
  }
}
