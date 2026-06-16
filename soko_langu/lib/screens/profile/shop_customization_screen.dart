import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_service.dart';
import '../../services/cloudinary_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../main.dart' show themeManager;

class ShopCustomizationScreen extends StatefulWidget {
  const ShopCustomizationScreen({super.key});

  @override
  State<ShopCustomizationScreen> createState() =>
      _ShopCustomizationScreenState();
}

class _ShopCustomizationScreenState extends State<ShopCustomizationScreen> {
  final _userService = UserService();
  final _picker = ImagePicker();

  bool _loading = false;
  String _banner = '';
  String _bannerColor = '';
  String _accentColor = '';
  bool _changed = false;

  List<Color> _presetColors() => [
    const Color(0xFFE53935), // Red
    const Color(0xFFD81B60), // Pink
    const Color(0xFF8E24AA), // Purple
    const Color(0xFF5E35B1), // Deep Purple
    const Color(0xFF3949AB), // Indigo
    const Color(0xFF1E88E5), // Blue
    const Color(0xFF039BE5), // Light Blue
    const Color(0xFF00ACC1), // Cyan
    const Color(0xFF00897B), // Teal
    const Color(0xFF43A047), // Green
    const Color(0xFF7CB342), // Light Green
    const Color(0xFFC0CA33), // Lime
    const Color(0xFFFDD835), // Yellow
    const Color(0xFFFFB300), // Amber
    const Color(0xFFFB8C00), // Orange
    const Color(0xFFFF7043), // Deep Orange
    const Color(0xFF8D6E63), // Brown
    const Color(0xFF78909C), // Blue Grey
    const Color(0xFF212121), // Near Black
    const Color(0xFFFFFFFF), // White
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile = await _userService.getProfile(uid);
    if (profile == null) return;
    setState(() {
      _banner = profile.shopBanner;
      _bannerColor = profile.shopBannerColor;
      _accentColor = profile.shopAccentColor;
    });
  }

  Future<void> _pickBanner() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final url = await CloudinaryService.uploadImage(file);
      setState(() {
        _banner = url;
        _changed = true;
      });
    } catch (e) {
      debugPrint('ShopCustomization banner upload: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.tr('error')}: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      await _userService.updateStorefront(uid, {
        'shopBanner': _banner,
        'shopBannerColor': _bannerColor,
        'shopAccentColor': _accentColor,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('storefront_updated'))),
        );
        setState(() => _changed = false);
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Color _parseColor(String hex) {
    if (hex.isEmpty) return Colors.transparent;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  String _colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  Future<Color?> _pickColor({String? initialHex}) async {
    final controller = TextEditingController(text: initialHex ?? '');
    return showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Custom Color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Hex color (e.g. #FF5733)',
                  border: OutlineInputBorder(),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                var hex = controller.text.trim();
                if (hex.isEmpty) return;
                if (!hex.startsWith('#')) hex = '#$hex';
                try {
                  Navigator.pop(ctx, _parseColor(hex));
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid hex color')),
                  );
                }
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomColorButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade400, width: 1.5),
        ),
        child: Icon(Icons.add, color: Colors.grey.shade600, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('shop_customization'))),
      body: SafeArea(child: _buildForm()),
      bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _changed && !_loading ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                      child: _loading
                      ? const GoogleLoading(size: 20, strokeWidth: 2)
                      : Text(context.tr('save')),
                ),
              ),
            ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPreview(),
          const SizedBox(height: 24),
          Text(
            context.tr('shop_banner'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickBanner,
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _bannerColor.isNotEmpty
                    ? _parseColor(_bannerColor)
                    : Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(12),
                image: _banner.isNotEmpty
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(_banner),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: Center(
                child: _banner.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 40,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('shop_banner_hint'),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('shop_banner_color'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._presetColors().map((c) {
                final hex = _colorToHex(c);
                final selected = _bannerColor == hex;
                return GestureDetector(
                  onTap: () => setState(() {
                    _bannerColor = hex;
                    _changed = true;
                  }),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(12),
                      border: selected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : null,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: selected
                        ? Icon(Icons.check, color: Theme.of(context).colorScheme.surface, size: 20)
                        : null,
                  ),
                );
              }),
              _buildCustomColorButton(
                onTap: () async {
                  final color = await _pickColor(initialHex: _bannerColor);
                  if (color != null) {
                    setState(() {
                      _bannerColor = _colorToHex(color);
                      _changed = true;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('shop_accent_color'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('shop_accent_color_hint'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._presetColors().map((c) {
                final hex = _colorToHex(c);
                final selected = _accentColor == hex;
                return GestureDetector(
                  onTap: () => setState(() {
                    _accentColor = hex;
                    _changed = true;
                  }),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(12),
                      border: selected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : null,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: selected
                        ? Icon(Icons.check, color: Theme.of(context).colorScheme.surface, size: 20)
                        : null,
                  ),
                );
              }),
              _buildCustomColorButton(
                onTap: () async {
                  final color = await _pickColor(initialHex: _accentColor);
                  if (color != null) {
                    setState(() {
                      _accentColor = _colorToHex(color);
                      _changed = true;
                    });
                  }
                },
              ),
            ],
          ),
          const Divider(height: 40),
          Text(
            'App Theme Color',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Change the entire app\'s color theme',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ..._presetColors().map((c) {
                final selected = themeManager.seedColor.value == c.value;
                return GestureDetector(
                  onTap: () => themeManager.setSeedColor(c),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(12),
                      border: selected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : null,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: selected
                        ? Icon(Icons.check, color: Theme.of(context).colorScheme.surface, size: 20)
                        : null,
                  ),
                );
              }),
              _buildCustomColorButton(
                onTap: () async {
                  final color = await _pickColor(
                    initialHex: _colorToHex(themeManager.seedColor),
                  );
                  if (color != null) {
                    themeManager.setSeedColor(color);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final accent = _accentColor.isNotEmpty
        ? _parseColor(_accentColor)
        : Theme.of(context).colorScheme.primary;
    final bgColor = _bannerColor.isNotEmpty
        ? _parseColor(_bannerColor)
        : Theme.of(context).colorScheme.surfaceContainerLow;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              image: _banner.isNotEmpty
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(_banner),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _banner.isEmpty
                ? Center(
                    child: Icon(Icons.store, size: 48, color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.54)),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: accent,
                  child: Icon(Icons.person, color: Theme.of(context).colorScheme.surface),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shop',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Seller',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
