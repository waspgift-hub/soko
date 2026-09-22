import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_reveal.dart';
import '../widgets/responsive_container.dart';
import '../widgets/section_header.dart';

/// Animated escrow journey: progress advances as the section appears.
class EscrowSection extends StatefulWidget {
  const EscrowSection({super.key});

  @override
  State<EscrowSection> createState() => _EscrowSectionState();
}

class _EscrowSectionState extends State<EscrowSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SokoBrand.ink,
      padding: const EdgeInsets.symmetric(vertical: 88),
      child: ResponsiveContainer(
        child: Column(
          children: [
            AnimatedReveal(
              onVisible: () {
                if (!MediaQuery.disableAnimationsOf(context)) {
                  _controller.forward();
                } else {
                  _controller.value = 1.0;
                }
              },
              child: _header(context),
            ),
            const SizedBox(height: 52),
            AnimatedBuilder(
              animation: _progress,
              builder: (_, _) => LayoutBuilder(
                builder: (context, c) =>
                    c.maxWidth < 760 ? _vertical() : _horizontal(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return SectionHeader(
      eyebrow: context.str('why_eyebrow'),
      title: context.str('escrow_title'),
      sub: context.str('escrow_sub'),
      center: true,
    );
  }

  Widget _horizontal() {
    return Builder(
      builder: (context) {
        final n = escrowSteps.length;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < n; i++) ...[
              Expanded(child: _Step(index: i, progress: _progress.value)),
              if (i != n - 1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 23),
                    child: _Connector(filled: _progress.value * n > i + 1),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _vertical() {
    return Builder(
      builder: (context) {
        final n = escrowSteps.length;
        return Column(
          children: [
            for (var i = 0; i < n; i++) ...[
              _Step(index: i, progress: _progress.value, horizontal: false),
              if (i != n - 1)
                _Connector(
                    filled: _progress.value * n > i + 1, vertical: true),
            ],
          ],
        );
      },
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final double progress;
  final bool horizontal;

  const _Step({
    required this.index,
    required this.progress,
    this.horizontal = true,
  });

  @override
  Widget build(BuildContext context) {
    final active = progress * escrowSteps.length > index;
    final node = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? SokoBrand.green : Colors.transparent,
        border: Border.all(
          color: active
              ? SokoBrand.green
              : Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: active
          ? const Icon(Icons.check, color: Colors.black, size: 22)
          : Text(
              '${index + 1}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    final label = Text(
      context.str(escrowSteps[index]),
      textAlign: horizontal ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
    );
    if (horizontal) {
      return Column(children: [node, const SizedBox(height: 10), label]);
    }
    return Row(children: [node, const SizedBox(width: 14), Expanded(child: label)]);
  }
}

class _Connector extends StatelessWidget {
  final bool filled;
  final bool vertical;
  const _Connector({required this.filled, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: vertical ? 26 : 2,
      width: vertical ? 2 : double.infinity,
      margin: vertical
          ? const EdgeInsets.only(left: 22)
          : const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color:
            filled ? SokoBrand.green : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
