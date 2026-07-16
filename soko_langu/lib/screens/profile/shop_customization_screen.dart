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
        const Color(0xFFE53935),
        const Color(0xFFD81B60),
        const Color(0xFF8E24AA),
        const Color(0xFF5E35B1),
        const Color(0xFF3949AB),
        const Color(0xFF1E88E5),
        const Color(0xFF039BE5),
        const Color(0xFF00ACC1),
        const Color(0xFF00897B),
        const Color(0xFF43A047),
        const Color(0xFF7CB342),
        const Color(0xFFC0CA33),
        const Color(0xFFFDD835),
        const Color(0xFFFFB300),
        const Color(0xFFFB8C00),
        const Color(0xFFFF7043),
        const Color(0xFF8D6E63),
        const Color(0xFF78909C),
        const Color(0xFF212121),
        const Color.fromARGB(255, 71, 7, 7),
      ];

  Future<Color?> _pickColor({Color? initial}) async {
    final controller = TextEditingController(
      text: _colorToHex(initial ?? themeManager.seedColor),
    );
    return showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.tr('custom_color')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: context.tr('hex_color_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetColors().map((c) {
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () {
                var hex = controller.text.trim();
                if (hex.isEmpty) return;
                if (!hex.startsWith('#')) hex = '#$hex';
                try {
                  hex = hex.replaceFirst('#', '');
                  if (hex.length == 6) hex = 'FF$hex';
                  Navigator.pop(ctx, Color(int.parse(hex, radix: 16)));
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('invalid_hex_color'))),
                  );
                }
              },
              child: Text(context.tr('apply')),
            ),
          ],
        );
      },
    );
  }

  String _colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

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
                  GestureDetector(
                    onTap: () async {
                      final color =
                          await _pickColor(initial: themeManager.seedColor);
                      if (color != null) {
                        themeManager.setSeedColor(color);
                      }
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.onSurface.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(Icons.add,
                          color: cs.onSurfaceVariant, size: 24),
                    ),
                  ),
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
