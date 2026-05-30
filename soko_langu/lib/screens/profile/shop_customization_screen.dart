import 'package:flutter/material.dart';
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

  static const _presetColors = [
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFFEF6C00),
    Color(0xFF00838F),
    Color(0xFF4E342E),
    Color(0xFF37474F),

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
    final file = await _picker.pickImage(source: ImageSource.gallery);
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
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                image: _banner.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(_banner),
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
                            color: Colors.grey[500],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('shop_banner_hint'),
                            style: TextStyle(color: Colors.grey[600]),
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
            children: _presetColors.map((c) {
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
                        ? Border.all(color: Colors.black, width: 3)
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
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('shop_accent_color'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('shop_accent_color_hint'),
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _presetColors.map((c) {
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
                        ? Border.all(color: Colors.black, width: 3)
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
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const Divider(height: 40),
          Text(
            'App Theme Color',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Change the entire app\'s color theme',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _presetColors.map((c) {
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
                        ? Border.all(color: Colors.black, width: 3)
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
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final accent = _accentColor.isNotEmpty
        ? _parseColor(_accentColor)
        : Colors.green;
    final bgColor = _bannerColor.isNotEmpty
        ? _parseColor(_bannerColor)
        : Colors.grey[100]!;

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
                      image: NetworkImage(_banner),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _banner.isEmpty
                ? Center(
                    child: Icon(Icons.store, size: 48, color: Colors.white54),
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
                  child: Icon(Icons.person, color: Colors.white),
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
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
