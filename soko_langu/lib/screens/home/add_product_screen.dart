import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/product_service.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../services/category_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../utils/network_error.dart';
import '../../app/app_transitions.dart';
import '../../widgets/barcode_scanner_widget.dart';
import '../../constants/tanzania_districts.dart';

class _VariantEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController valueCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController(text: '0');
  void dispose() {
    nameCtrl.dispose();
    valueCtrl.dispose();
    priceCtrl.dispose();
    stockCtrl.dispose();
  }
}

class AddProductScreen extends StatefulWidget {
  final Product? product;

  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController(text: '1');
  final _brandController = TextEditingController();
  final _locationController = TextEditingController();
  final _barcodeController = TextEditingController();

  String _selectedCategory = 'Electronics';
  String _selectedSubcategory = '';
  String _selectedCondition = 'new';
  String _selectedDistrict = '';
  List<SubCategory> _subcategories = [];
  List<XFile> _newImages = [];
  List<String> _existingImages = [];
  List<Map<String, dynamic>> _existingMeta = [];
  List<Map<String, dynamic>> _newMeta = [];
  XFile? _videoFile;
  String? _existingVideoUrl;
  bool _isWholesale = false;
  bool _saving = false;
  List<_VariantEntry> _variants = [];

  void _addVariant() => setState(() => _variants.add(_VariantEntry()));
  void _removeVariant(int i) => setState(() => _variants.removeAt(i));

  List<Map<String, dynamic>> _buildVariantData() => _variants
      .where((v) => v.nameCtrl.text.isNotEmpty && v.valueCtrl.text.isNotEmpty)
      .map(
        (v) => {
          'id':
              DateTime.now().millisecondsSinceEpoch.toString() +
              v.nameCtrl.text,
          'name': v.nameCtrl.text,
          'value': v.valueCtrl.text,
          'priceAdjustment': double.tryParse(v.priceCtrl.text) ?? 0,
          'stock': int.tryParse(v.stockCtrl.text) ?? 0,
        },
      )
      .toList();

  final ProductService _productService = ProductService();
  final ImagePicker _picker = ImagePicker();

  List<Category> _categories = getDefaultCategories();

  List<String> get _allDistricts => kRegionDistricts.values
      .expand((d) => d)
      .toSet()
      .toList()
    ..sort();

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (_isEditing) _prefillFields();
  }

  void _prefillFields() {
    final p = widget.product!;
    _nameController.text = p.name;
    _descriptionController.text = p.description;
    _priceController.text = p.price.toString();
    _stockController.text = p.stock.toString();
    _selectedCategory = p.category;
    _selectedSubcategory = p.subcategory;
    _selectedCondition = p.condition;
    _isWholesale = p.isWholesale;
    _existingImages = List.from(p.images);
    _existingVideoUrl = p.videoUrl;
    if (p.imageMetadata != null && p.imageMetadata!.length == _existingImages.length) {
      _existingMeta = List.from(p.imageMetadata!);
    }
    if (p.brand != null) _brandController.text = p.brand!;
    if (p.location.isNotEmpty) _locationController.text = p.location;
    if (p.district.isNotEmpty) _selectedDistrict = p.district;
    if (p.barcode != null) _barcodeController.text = p.barcode!;
    for (var v in p.variants) {
      final entry = _VariantEntry();
      entry.nameCtrl.text = v.name;
      entry.valueCtrl.text = v.value;
      entry.priceCtrl.text = v.priceAdjustment?.toStringAsFixed(0) ?? '0';
      entry.stockCtrl.text = v.stock.toString();
      _variants.add(entry);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _brandController.dispose();
    _locationController.dispose();
    _barcodeController.dispose();
    for (var v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  void _loadCategories() {
    CategoryService().getCategories().listen((categories) {
      if (mounted) {
        setState(() {
          _categories = categories.isNotEmpty
              ? categories
              : getDefaultCategories();
          _updateSubcategories();
        });
      }
    });
  }

  void _updateSubcategories() {
    final category = _categories.isEmpty
        ? null
        : _categories.firstWhere(
            (c) => c.name == _selectedCategory,
            orElse: () => _categories.first,
          );
    if (category == null) return;
    setState(() {
      _subcategories = category.subcategories;
      if (_subcategories.isNotEmpty &&
          !_subcategories.any((s) => s.name == _selectedSubcategory)) {
        _selectedSubcategory = _subcategories.first.name;
      }
    });
  }

  Future<void> _pickImages() async {
    final remaining = 5 - _existingImages.length - _newImages.length;
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('max_5_images', 'Max 5 photos'))),
        );
      }
      return;
    }
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.tr('take_photo', 'Piga picha')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title:
                  Text(context.tr('choose_gallery', 'Chagua kutoka albamu')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;
    if (src == ImageSource.camera) {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (shot == null) return;
      final meta = await _decodeSize(shot);
      if (!mounted) return;
      setState(() {
        _newImages.add(shot);
        _newMeta.add(meta);
      });
      return;
    }
    final List<XFile> images = await _picker.pickMultiImage(
      maxWidth: 1024,
      imageQuality: 80,
      limit: remaining,
    );
    if (images.isEmpty) return;
    final meta = await Future.wait(images.map(_decodeSize));
    if (!mounted) return;
    setState(() {
      _newImages.addAll(images);
      _newMeta.addAll(meta);
    });
  }

  Future<Map<String, dynamic>> _decodeSize(XFile xfile) async {
    try {
      final bytes = await xfile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final size = <String, dynamic>{'width': img.width, 'height': img.height};
      img.dispose();
      return size;
    } catch (e) {
      return <String, dynamic>{'width': null, 'height': null};
    }
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _videoFile = picked);
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImages.removeAt(index);
      if (index < _existingMeta.length) _existingMeta.removeAt(index);
    });
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
      if (index < _newMeta.length) _newMeta.removeAt(index);
    });
  }

  int _mediaCount() => _existingImages.length + _newImages.length;

  /// Picha ya kwanza ndiyo kava. Hamisha picha kwenda mbele kwenye orodha
  /// yake (pamoja na metadata yake) bila kuvunja mpangilio.
  void _makeCover(int globalIndex) {
    if (globalIndex <= 0) return;
    if (globalIndex < _existingImages.length) {
      setState(() {
        final img = _existingImages.removeAt(globalIndex);
        _existingImages.insert(0, img);
        if (globalIndex < _existingMeta.length) {
          final m = _existingMeta.removeAt(globalIndex);
          _existingMeta.insert(0, m);
        }
      });
      return;
    }
    if (_existingImages.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'remove_old_first',
              'Ondoa picha za zamani kwanza ili hii iwe kava',
            ),
          ),
        ),
      );
      return;
    }
    final li = globalIndex - _existingImages.length;
    setState(() {
      final f = _newImages.removeAt(li);
      _newImages.insert(0, f);
      if (li < _newMeta.length) {
        final m = _newMeta.removeAt(li);
        _newMeta.insert(0, m);
      }
    });
  }

  Widget _brokenImage({double iconSize = 24}) => Container(
        color: Colors.grey.shade300,
        child: Icon(Icons.broken_image, size: iconSize),
      );

  Widget _coverImage() {
    final ImageProvider provider = _existingImages.isNotEmpty
        ? NetworkImage(_existingImages.first)
        : FileImage(File(_newImages.first.path));
    return Image(
      image: provider,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (context, error, stackTrace) =>
          _brokenImage(iconSize: 48),
    );
  }

  Widget _addThumb() {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.5),
          ),
          color: cs.primary.withValues(alpha: 0.07),
        ),
        child: Icon(Icons.add_a_photo_outlined, color: cs.primary),
      ),
    );
  }

  Widget _thumbTile(int globalIndex) {
    final cs = Theme.of(context).colorScheme;
    final isExisting = globalIndex < _existingImages.length;
    final isCover = globalIndex == 0;
    final Widget img = isExisting
        ? Image.network(
            _existingImages[globalIndex],
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _brokenImage(),
          )
        : Image.file(
            File(_newImages[globalIndex - _existingImages.length].path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _brokenImage(),
          );
    return Container(
      width: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCover ? cs.primary : cs.outline.withValues(alpha: 0.4),
          width: isCover ? 2.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            img,
            if (isCover)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'KAVA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: 2,
                bottom: 2,
                child: GestureDetector(
                  onTap: () => _makeCover(globalIndex),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.star_outline,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => isExisting
                    ? _removeExistingImage(globalIndex)
                    : _removeNewImage(
                        globalIndex - _existingImages.length,
                      ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: cs.error,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, size: 14, color: cs.surface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      buildAppRoute(builder: (_) => const BarcodeScannerWidget()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _barcodeController.text = result;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final tr = context.tr;

    if (_existingImages.isEmpty && _newImages.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(tr('upload_image'))));
      return;
    }

    final priceText = _priceController.text.replaceAll(',', '').trim();
    final stockText = _stockController.text.replaceAll(',', '').trim();
    final parsedPrice = double.tryParse(priceText);
    final parsedStock = int.tryParse(stockText);
    if (parsedPrice == null || parsedPrice <= 0) {
      messenger.showSnackBar(SnackBar(content: Text(tr('enter_valid_price'))));
      setState(() => _saving = false);
      return;
    }
    if (parsedStock == null || parsedStock < 0) {
      messenger.showSnackBar(SnackBar(content: Text(tr('enter_valid_stock'))));
      setState(() => _saving = false);
      return;
    }

    setState(() => _saving = true);
    try {
      final variantData = _buildVariantData();
      if (_isEditing) {
        await _productService.updateProduct(
          productId: widget.product!.id,
          name: _nameController.text,
          description: _descriptionController.text,
          price: parsedPrice,
          category: _selectedCategory,
          subcategory: _selectedSubcategory,
          stock: parsedStock,
          isWholesale: _isWholesale,
          variants: variantData.isNotEmpty ? variantData : null,
          brand: _brandController.text.isNotEmpty
              ? _normalizeBrand(_brandController.text)
              : null,
          condition: _selectedCondition,
          location: _locationController.text.isNotEmpty
              ? _locationController.text
              : null,
          district: _selectedDistrict.isEmpty ? null : _selectedDistrict,
          barcode: _barcodeController.text.isNotEmpty
              ? _barcodeController.text.trim()
              : null,
          existingImages: _existingImages.isNotEmpty ? _existingImages : null,
          newImages: _newImages.isNotEmpty ? _newImages : null,
          imageMetadata: [..._existingMeta, ..._newMeta].isEmpty
              ? null
              : [..._existingMeta, ..._newMeta],
          newVideoFile: _videoFile,
          videoUrl: _videoFile == null ? _existingVideoUrl : null,
        );
      } else {
        await _productService.addProduct(
          name: _nameController.text,
          description: _descriptionController.text,
          price: parsedPrice,
          category: _selectedCategory,
          subcategory: _selectedSubcategory,
          currency: 'TZS',
          stock: parsedStock,
          imageFiles: _newImages,
          imageMetadata: _newMeta.isEmpty ? null : _newMeta,
          videoFile: _videoFile,
          videoUrl: _videoFile == null ? _existingVideoUrl : null,
          location: _locationController.text.isNotEmpty
              ? _locationController.text
              : 'Tanzania',
          district: _selectedDistrict,
          isWholesale: _isWholesale,
          variants: variantData.isNotEmpty ? variantData : null,
          brand: _brandController.text.isNotEmpty
              ? _normalizeBrand(_brandController.text)
              : null,
          condition: _selectedCondition,
          barcode: _barcodeController.text.isNotEmpty
              ? _barcodeController.text.trim()
              : null,
        );
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? tr('product_updated') : tr('product_added'),
          ),
        ),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final internalMsg = e is NetworkError ? '${e.message} ${e.originalError}' : msg;
      if (msg.contains('permission') || msg.contains('PERMISSION_DENIED') ||
          msg.contains('caller does not have permission')) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('error')}: ${context.tr('permission_denied')}. ${context.tr('try_again')}',
            ),
          ),
        );
      } else if (internalMsg.contains('KYC') || internalMsg.contains('kyc')) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.tr('kyc_required_selling')),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.trError(e)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _normalizeBrand(String brand) {
    final trimmed = brand.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? context.tr('update_product')
              : context.tr('sell_product'),
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const GoogleLoading(size: 20, strokeWidth: 2)
                : Text(
                    _isEditing
                        ? context.tr('update_product').toUpperCase()
                        : context.tr('sell_product').toUpperCase(),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).viewInsets.bottom + 160,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('product_images'),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_existingImages.length + _newImages.length}/5',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('cover_hint',
                      'Picha ya kwanza ndiyo kava inayoonekana sokoni'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                if (_existingImages.isEmpty && _newImages.isEmpty)
                  GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.06),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('add_photos', 'Ongeza picha'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          Text(
                            context.tr(
                                'up_to_5', 'Hadi 5 • Kamera au albamu'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        SizedBox(
                          height: 210,
                          width: double.infinity,
                          child: _coverImage(),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              context.tr('cover_badge', 'KAVA'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          _mediaCount() + (_mediaCount() < 5 ? 1 : 0),
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index == _mediaCount() &&
                            _mediaCount() < 5) {
                          return _addThumb();
                        }
                        return _thumbTile(index);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  context.tr('product_video', 'Video ya bidhaa (hiari)'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 8),
                if (_videoFile == null && _existingVideoUrl == null)
                  GestureDetector(
                    onTap: _pickVideo,
                    child: Container(
                      height: 84,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.6),
                        ),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.tr(
                                'add_video', 'Add video (max 1)'),
                            style: TextStyle(
                              color:
                                  Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Stack(
                    children: [
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Colors.black87, Colors.black54],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_circle_fill,
                              size: 52,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _videoFile != null
                                  ? context.tr('new_video',
                                      'Video mpya imechaguliwa')
                                  : context.tr('saved_video',
                                      'Video iliyohifadhiwa'),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _videoFile = null;
                            _existingVideoUrl = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: context.tr('product_name'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  validator: (v) => v!.isEmpty ? context.tr('required') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: context.tr('description'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  maxLines: 3,
                  validator: (v) => v!.isEmpty ? context.tr('required') : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: InputDecoration(
                          labelText: context.tr('price'),
                          border: const OutlineInputBorder(),
                          labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v!.isEmpty ? context.tr('required') : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        decoration: InputDecoration(
                          labelText: context.tr('stock'),
                          border: const OutlineInputBorder(),
                          labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v!.isEmpty ? context.tr('required') : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _brandController,
                  decoration: InputDecoration(
                    labelText: context.tr('brand'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcodeController,
                  decoration: InputDecoration(
                  labelText: context.tr('barcode_label'),
                  hintText: context.tr('barcode_hint'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.qr_code_scanner, color: Theme.of(context).colorScheme.primary),
                      onPressed: () => _scanBarcode(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    labelText: context.tr('location'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedDistrict.isEmpty ? null : _selectedDistrict,
                  decoration: InputDecoration(
                    labelText: context.tr('district'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  items: _allDistricts
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedDistrict = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: context.tr('category'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  items: _categories
                      .map(
                        (cat) => DropdownMenuItem(
                          value: cat.name,
                          child: Text(
                            '${cat.nameSw} | ${cat.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                      _updateSubcategories();
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_subcategories.isNotEmpty)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedSubcategory.isNotEmpty
                        ? _selectedSubcategory
                        : null,
                    decoration: InputDecoration(
                      labelText: context.tr('subcategory'),
                      border: const OutlineInputBorder(),
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                    items: _subcategories
                        .map(
                          (sub) => DropdownMenuItem(
                            value: sub.name,
                            child: Text(
                              '${sub.nameSw} | ${sub.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedSubcategory = value!),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedCondition,
                  decoration: InputDecoration(
                    labelText: context.tr('condition'),
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'new',
                      child: Text(context.tr('new')),
                    ),
                    DropdownMenuItem(
                      value: 'used',
                      child: Text(context.tr('used')),
                    ),
                    DropdownMenuItem(
                      value: 'refurbished',
                      child: Text(context.tr('refurbished')),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedCondition = value!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      context.tr('wholesale'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: _isWholesale,
                      onChanged: (value) => setState(() => _isWholesale = value),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('variants'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(context.tr('add')),
                      onPressed: _addVariant,
                    ),
                  ],
                ),
                ..._variants.asMap().entries.map((entry) {
                  final i = entry.key;
                  final v = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: v.nameCtrl,
                                  decoration: InputDecoration(
                                    labelText: context.tr('name_eg'),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.close,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  onPressed: () => _removeVariant(i),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: v.valueCtrl,
                                  decoration: InputDecoration(
                                    labelText: context.tr('value_eg'),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                flex: 2,
                                child: TextField(
                                  controller: v.priceCtrl,
                                  decoration: InputDecoration(
                                    labelText: context.tr('price_adj_label'),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                flex: 1,
                                child: TextField(
                                  controller: v.stockCtrl,
                                  decoration: InputDecoration(
                                    labelText: context.tr('stock'),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
