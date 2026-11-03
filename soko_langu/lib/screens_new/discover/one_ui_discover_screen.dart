import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design_system/tokens/one_ui_tokens.dart';

class OneUiDiscoverScreen extends StatefulWidget {
  const OneUiDiscoverScreen({super.key});

  @override
  State<OneUiDiscoverScreen> createState() => _OneUiDiscoverScreenState();
}

class _OneUiDiscoverScreenState extends State<OneUiDiscoverScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
      appBar: AppBar(
        backgroundColor: isDark ? OneUiColors.darkBackground : OneUiColors.background,
        title: Text(
          'Discover',
          style: TextStyle(color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(OneUiSpacing.xl),
        children: [
          Text(
            'Explore Categories',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
            ),
          ),
          const SizedBox(height: OneUiSpacing.lg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: OneUiSpacing.md,
              mainAxisSpacing: OneUiSpacing.md,
              childAspectRatio: 1.3,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              final items = [
                {'icon': Icons.phone_android, 'label': 'Electronics', 'color': Colors.blue},
                {'icon': Icons.checkroom, 'label': 'Fashion', 'color': Colors.pink},
                {'icon': Icons.home, 'label': 'Home & Living', 'color': Colors.orange},
                {'icon': Icons.directions_car, 'label': 'Vehicles', 'color': Colors.green},
                {'icon': Icons.sports_soccer, 'label': 'Sports', 'color': Colors.red},
                {'icon': Icons.more_horiz, 'label': 'More', 'color': Colors.purple},
              ];
              final item = items[index];
              return GestureDetector(
                onTap: () => HapticFeedback.lightImpact(),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? OneUiColors.darkSurface : OneUiColors.surface,
                    borderRadius: BorderRadius.circular(OneUiRadius.lg),
                    border: Border.all(color: isDark ? OneUiColors.darkBorder : OneUiColors.border, width: 0.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item['icon'] as IconData, color: item['color'] as Color, size: 32),
                      const SizedBox(height: OneUiSpacing.sm),
                      Text(
                        item['label'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? OneUiColors.darkTextPrimary : OneUiColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
