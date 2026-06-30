import 'dart:async';
import 'package:flutter/material.dart';
import '../models/flash_sale_model.dart';
import '../services/price_drop_service.dart';
import 'flash_sale_banner.dart';
import 'price_drop_banner.dart';
import 'dynamic_banner.dart';

class BannerRotator extends StatefulWidget {
  final List<FlashSale> flashSales;
  const BannerRotator({super.key, required this.flashSales});

  @override
  State<BannerRotator> createState() => _BannerRotatorState();
}

class _BannerRotatorState extends State<BannerRotator> {
  int _current = 0;
  Timer? _timer;
  bool _hasPriceDrops = false;
  StreamSubscription? _priceSub;

  @override
  void initState() {
    super.initState();
    _priceSub = PriceDropService()
        .getActivePriceDrops()
        .listen((drops) {
      if (mounted) setState(() => _hasPriceDrops = drops.isNotEmpty);
    });
  }

  @override
  void didUpdateWidget(BannerRotator old) {
    super.didUpdateWidget(old);
    final changed = old.flashSales.length != widget.flashSales.length ||
        (widget.flashSales.isNotEmpty &&
            old.flashSales.isNotEmpty &&
            old.flashSales.first.id != widget.flashSales.first.id);
    if (changed) {
      _timer?.cancel();
      _timer = null;
      if (mounted) setState(() { _current = 0; _startTimer(); });
    }
  }

  void _startTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final c = _banners().length;
      if (c <= 1) { _timer?.cancel(); _timer = null; return; }
      setState(() => _current = (_current + 1) % c);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _priceSub?.cancel();
    super.dispose();
  }

  List<Widget> _banners() {
    final list = <Widget>[];
    if (widget.flashSales.isNotEmpty) {
      list.add(FlashSaleBanner(key: const ValueKey('flash_banner'), sales: widget.flashSales));
    }
    if (_hasPriceDrops) {
      list.add(const PriceDropBanner(key: ValueKey('price_drop_banner')));
    }
    list.add(const DynamicBanner(key: ValueKey('dynamic_banner')));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final banners = _banners();
    final count = banners.length;

    if (count == 0) return const SizedBox.shrink();
    if (count == 1) {
      _timer?.cancel();
      _timer = null;
      return banners.first;
    }

    final idx = _current < count ? _current : 0;
    _startTimer();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: KeyedSubtree(
            key: ValueKey('banner_$idx'),
            child: banners[idx],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(count, (i) {
            final active = i == idx;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 22 : 8,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
