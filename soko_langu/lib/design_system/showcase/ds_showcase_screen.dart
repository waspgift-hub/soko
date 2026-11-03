import 'package:flutter/material.dart';
import '../../design_system/soko_vibe_ds.dart';

class DsShowcaseScreen extends StatefulWidget {
  const DsShowcaseScreen({super.key});

  @override
  State<DsShowcaseScreen> createState() => _DsShowcaseScreenState();
}

class _DsShowcaseScreenState extends State<DsShowcaseScreen> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: context.ds.scaffoldBg,
      appBar: AppBar(
        title: Text('Soko Vibe Design System', style: Ds.appBarTitle(cs.onSurface)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Ds.sp4),
        children: [
          DSSectionHeader(title: 'Colors', subtitle: 'Semantic tokens'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Ds.sp4),
              child: Wrap(
                spacing: Ds.sp3,
                runSpacing: Ds.sp3,
                children: [
                  _colorChip(cs.primary, 'Primary'),
                  _colorChip(cs.secondary, 'Secondary'),
                  _colorChip(cs.surface, 'Surface'),
                  _colorChip(cs.error, 'Error'),
                  _colorChip(cs.tertiary, 'Tertiary'),
                ],
              ),
            ),
          ),
          const SizedBox(height: Ds.sp6),
          DSSectionHeader(title: 'Typography', subtitle: 'One UI scale'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Ds.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Display Large', style: Ds.displayLg(cs.onSurface)),
                  const SizedBox(height: Ds.sp2),
                  Text('Screen Title', style: Ds.screenTitle(cs.onSurface)),
                  const SizedBox(height: Ds.sp2),
                  Text('Section Title', style: Ds.sectionTitle(cs.onSurface)),
                  const SizedBox(height: Ds.sp2),
                  Text('Body Medium - The quick brown fox jumps over the lazy dog', style: Ds.bodyMd(cs.onSurface)),
                  const SizedBox(height: Ds.sp2),
                  Text('Label Medium', style: Ds.labelMd(cs.onSurface)),
                ],
              ),
            ),
          ),
          const SizedBox(height: Ds.sp6),
          DSSectionHeader(title: 'Buttons', subtitle: 'Variants'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Ds.sp4),
              child: Wrap(
                spacing: Ds.sp3,
                runSpacing: Ds.sp3,
                children: [
                  DSButton(label: 'Primary', onPressed: () {}),
                  DSButton(label: 'Secondary', variant: DSButtonVariant.secondary, onPressed: () {}),
                  DSButton(label: 'Ghost', variant: DSButtonVariant.ghost, onPressed: () {}),
                  DSButton(label: 'Destructive', variant: DSButtonVariant.destructive, onPressed: () {}),
                ],
              ),
            ),
          ),
          const SizedBox(height: Ds.sp6),
          DSSectionHeader(title: 'Components', subtitle: 'Cards, chips, inputs'),
          const DSCard(
            child: Padding(
              padding: EdgeInsets.all(Ds.sp4),
              child: Text('Card with consistent radius & spacing'),
            ),
          ),
          const SizedBox(height: Ds.sp4),
          Wrap(
            spacing: Ds.sp2,
            children: const [
              DSChip(label: 'All'),
              DSChip(label: 'Verified'),
              DSChip(label: 'Near Me'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colorChip(Color c, String label) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(Ds.rMd),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(height: Ds.sp1),
        Text(label, style: Ds.labelSm(Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }
}
