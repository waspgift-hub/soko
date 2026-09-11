import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../main.dart' show themeManager;

class ShopCustomizationScreen extends StatefulWidget {
  const ShopCustomizationScreen({super.key});

  @override
  State<ShopCustomizationScreen> createState() =>
      _ShopCustomizationScreenState();
}

class _ShopCustomizationScreenState extends State<ShopCustomizationScreen> {
  List<Color> _presetColors() => [
        const Color(0xFF9CD9B0),
        const Color(0xFF000000),
        const Color(0xFF1C1C1C),
        const Color(0xFF3B3B3B),
        const Color(0xFF616161),
        const Color(0xFF9E9E9E),
        const Color(0xFFFFFFFF),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('shop_customization'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      themeManager.seedColor.withValues(alpha: 0.1),
                      cs.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: themeManager.seedColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: themeManager.seedColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.palette_outlined,
                        color: themeManager.seedColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('app_theme_color'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('change_app_color_theme'),
                            style: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ..._presetColors().map((c) {
                    final selected = themeManager.seedColor.value == c.value;
                    return GestureDetector(
                      onTap: () => themeManager.setSeedColor(c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(16),
                          border: selected
                              ? Border.all(
                                  color: cs.onSurface, width: 3)
                              : Border.all(
                                  color: c.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: selected
                            ? Icon(Icons.check,
                                color: cs.surface, size: 24)
                            : null,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
