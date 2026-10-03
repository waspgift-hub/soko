import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/product_service.dart';
import '../../models/product_publish_stage.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../services/category_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/product_preview_sheet.dart';
import '../../services/transfer/transfer_item.dart';
import '../../services/transfer/transfer_progress.dart';
import '../../widgets/transfer/media_upload_list.dart';
import '../../widgets/transfer/transfer_progress_bar.dart';
import '../../theme/design_tokens.dart';
import '../../utils/network_error.dart';
import '../../app/app_transitions.dart';
import '../../app/routes.dart';
import '../../app/router.dart';
import '../../widgets/barcode_scanner_widget.dart';
import '../../widgets/safe_dropdown.dart';
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
  final List<String>? initialMediaPaths;

  const AddProductScreen({super.key, this.product, this.initialMediaPaths});

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

  /// Current publish phase, so the UI shows what is actually happening instead
  /// of an unexplained spinner.
  ProductPublishStage? _publishStage;

  /// Live upload batch while photos are being sent, so the screen can render
  /// one real progress row per file. Null outside an upload.
  TransferBatch? _activeBatch;

  /// Human-readable label for the current phase. Kept as a getter so the copy
  /// always matches the stage the service is actually in.
  String? get _publishStageLabel {
    final stage = _publishStage;
    if (stage == null) return null;
    return switch (stage) {
      ProductPublishStage.checking => context.tr('publishing_check'),
      ProductPublishStage.uploadingImages =>
        context.tr('publishing_uploading_images'),
      ProductPublishStage.saving => context.tr('publishing_saving'),
      ProductPublishStage.uploadingVideo =>
        context.tr('publishing_uploading_video'),
      ProductPublishStage.done => context.tr('publishing_done'),
    };
  }

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

  // getCategories() is a Stream (Firestore snapshots, or the HTTP v1 tree), so
  // it cannot seed a field. The static tree is the correct seed here: it renders
  // the dropdown on the first frame with no network wait, and _loadCategories()
  // swaps in the live list once it arrives. Seeding from the stream's first
  // emission instead would leave the category dropdown empty and un-tappable
  // until the network answered, and `orElse: () => _categories.first` in
  // _updateSubcategories() would throw on the empty list.
  List<Category> _categories = getDefaultCategories().where((c) => c.isActive).toList();

  List<String> get _allDistricts => kRegionDistricts.values
      .expand((d) => d)
      .toSet()
      .toList()
    ..sort();

  bool get _isEditing => widget.product != null;

  StreamSubscription<List<Category>>? _categoriesSub;

  bool get _hasUnsavedChanges {
    return _nameController.text.trim().isNotEmpty ||
        _descriptionController.text.trim().isNotEmpty ||
        _priceController.text.trim().isNotEmpty ||
        _newImages.isNotEmpty ||
        _videoFile != null ||
        _variants.isNotEmpty;
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges || _isEditing) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('discard_draft', 'Tupa rasimu?')),
        content: Text(context.tr(
            'discard_draft_body', 'Umejaza sehemu ya tangazo. Ukirudi nyuma, maelezo yatafutika.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('keep_editing', 'Endelea')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('discard', 'Tupa')),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  void initState() {
    super.initState();
    _updateSubcategories();
    if (_isEditing) _prefillFields();
    _handleInitialSharedMedia();
    _loadCategories();
  }

  /// Replaces the static seed with the live category list.
  ///
  /// Guarded on mounted and on a non-empty result: a Firestore error or an empty
  /// collection must leave the static tree in place, because the dropdown's
  /// `orElse: () => _categories.first` throws on an empty list.
  void _loadCategories() {
    _categoriesSub = CategoryService().watchCategories().listen((cats) {
      if (!mounted || cats.isEmpty) return;
      setState(() {
        _categories = cats.where((c) => c.isActive).toList();
        if (_categories.isEmpty) return;
        _updateSubcategories();
      });
    }, onError: (_) {
      // Static seed stays; the seller can still post under the default tree.
    });
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

  bool _sharedBannerSeen = false;

  void _handleInitialSharedMedia() {
    final paths = widget.initialMediaPaths;
    if (paths == null || paths.isEmpty) {
      // also check service pending (cold start via native)
      return;
    }
    // Show banner once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sharedBannerSeen && mounted) {
        _sharedBannerSeen = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('media_received', 'Media received — ready to sell on Soko Vibe')),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    });
    // Attach images/videos — respect 5 image limit
    for (final p in paths) {
      final lower = p.toLowerCase();
      final isVideo = lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.mkv') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.3gp');
      if (isVideo) {
        _videoFile ??= XFile(p);
      } else {
        if (_newImages.length + _existingImages.length < 5) {
          _newImages.add(XFile(p));
          // decode size async
          _decodeSize(XFile(p)).then((m) {
            if (mounted) setState(() => _newMeta.add(m));
          });
        }
      }
    }
  }

  @override
  void dispose() {
    // Cancel the Firestore category subscription before tearing down state, or
    // an in-flight snapshot calls setState on a disposed State.
    _categoriesSub?.cancel();
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

  void _updateSubcategories() {
    final normalizedSelected = normalizeCategory(_selectedCategory);
    final category = _categories.isEmpty
        ? null
        : _categories.firstWhere(
            (c) => normalizeCategory(c.name) == normalizedSelected,
            orElse: () => _categories.first,
          );
    if (category == null) return;
    _subcategories = category.subcategories;
    if (_subcategories.isNotEmpty && !_subcategories.any((s) => normalizeCategory(s.name) == normalizeCategory(_selectedSubcategory))) {
      _selectedSubcategory = _subcategories.first.name;
    }
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
        // 2000px @ q95 → the R2/Cloudinary pipeline downsizes to 1600px WebP;
        // picking at q80/1024px double-compressed too early and looked soft
        // in the product detail gallery.
        maxWidth: 2000,
        imageQuality: 95,
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
      maxWidth: 2000,
      imageQuality: 95,
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
    final Widget img = GestureDetector(
      onTap: () => _showImagePreview(globalIndex),
      child: isExisting
          ? Image.network(
              _existingImages[globalIndex],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _brokenImage(),
            )
          : Image.file(
              File(_newImages[globalIndex - _existingImages.length].path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _brokenImage(),
            ),
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

  void _showImagePreview(int globalIndex) {
    final isExisting = globalIndex < _existingImages.length;
    final ImageProvider provider = isExisting
        ? NetworkImage(_existingImages[globalIndex])
        : FileImage(
            File(_newImages[globalIndex - _existingImages.length].path));
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            maxScale: 4,
            child: Image(
              image: provider,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _brokenImage(iconSize: 56),
            ),
          ),
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

    final priceText = _priceController.text.replaceAll(',', '').trim();
    final parsedPrice = double.tryParse(priceText);
    if (parsedPrice == null || parsedPrice <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('enter_valid_price'))));
      return;
    }

    // Onyesho la bidhaa kabla ya kuchapisha. Picha zilizochaguliwa bado ziko
    // ndani ya simu, hivyo preview inaonyesha haraka bila kupakia chochote.
    final confirmed = await _confirmPreview(parsedPrice);
    if (!confirmed || !mounted) return;

    await _publish(parsedPrice);
  }

  /// Shows the buyer-facing preview and returns true when the seller confirms.
  Future<bool> _confirmPreview(double price) async {
    final stockText = _stockController.text.replaceAll(',', '').trim();
    return ProductPreviewSheet.show(
      context,
      preview: ProductPreviewSheet(
        name: _nameController.text,
        price: price,
        category: _selectedCategory,
        subcategory: _selectedSubcategory,
        stock: int.tryParse(stockText) ?? 0,
        condition: _selectedCondition,
        description: _descriptionController.text,
        brand: _brandController.text,
        location: _locationController.text,
        district: _selectedDistrict,
        isWholesale: _isWholesale,
        variants: _buildVariantData(),
        sellerId: FirebaseAuth.instance.currentUser?.uid ?? '',
        newImagePaths: _newImages.map((f) => f.path).toList(),
        existingImageUrls: _existingImages,
        hasVideo: _videoFile != null || (_existingVideoUrl?.isNotEmpty ?? false),
        publishLabel: _isEditing
            ? context.tr('update_product')
            : context.tr('sell_product'),
        isEditing: _isEditing,
      ),
    );
  }

  Future<void> _publish(double parsedPrice) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final tr = context.tr;

    if (_existingImages.isEmpty && _newImages.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(tr('upload_image'))));
      return;
    }

    final stockText = _stockController.text.replaceAll(',', '').trim();
    final parsedStock = int.tryParse(stockText);
    if (parsedStock == null || parsedStock < 0) {
      messenger.showSnackBar(SnackBar(content: Text(tr('enter_valid_stock'))));
      return;
    }

    setState(() {
      _saving = true;
      _publishStage = ProductPublishStage.checking;
    });
    String? createdId;
    try {
      final variantData = _buildVariantData();

      // Step 1 of publish: upload the picked photos as independently tracked
      // items so the seller sees one real row per file. Done here rather than
      // inside the service because the rows are UI state; the service is handed
      // the resulting URLs so nothing is uploaded twice.
      final List<String>? uploadedImageUrls = await _uploadPickedImages();

      // The seller dismissed the retry sheet, or gave up on this batch.
      if (!mounted || uploadedImageUrls == null) return;

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
          uploadedNewImages: uploadedImageUrls.isEmpty
              ? null
              : uploadedImageUrls,
          imageMetadata: [..._existingMeta, ..._newMeta].isEmpty
              ? null
              : [..._existingMeta, ..._newMeta],
          newVideoFile: _videoFile,
          videoUrl: _videoFile == null ? _existingVideoUrl : null,
        );
      } else {
        createdId = await _productService.addProduct(
          name: _nameController.text,
          description: _descriptionController.text,
          price: parsedPrice,
          category: _selectedCategory,
          subcategory: _selectedSubcategory,
          currency: 'TZS',
          stock: parsedStock,
          imageFiles: _newImages,
          imageUrls: uploadedImageUrls,
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
          onProgress: (stage) {
            if (mounted) setState(() => _publishStage = stage);
          },
        );
      }

      if (!mounted) return;
      // Video is uploaded after the listing is live, so the seller is told up
      // front instead of wondering where their clip went.
      if (_videoFile != null && createdId != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr('video_will_attach'))),
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? tr('product_updated') : tr('product_added'),
          ),
        ),
      );
      if (createdId != null) {
        _openCreatedProduct(createdId);
      } else {
        navigator.pop();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final internalMsg = e is NetworkError ? '${e.message} ${e.originalError}' : msg;
      if (msg.contains('permission') || msg.contains('PERMISSION_DENIED') ||
          msg.contains('caller does not have permission')) {
        // Onyesha pia hatua iliyoshindwa (kutoka step=...) ili ripoti iwe sahihi.
        final detail = internalMsg.length > 140
            ? '${internalMsg.substring(0, 140)}…'
            : internalMsg;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('error')}: ${context.tr('permission_denied')}. ${context.tr('try_again')}\n$detail',
            ),
            duration: const Duration(seconds: 8),
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
            content: Text(context.trError(e, feature: 'product', screen: 'add_product')),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Uploads the newly picked photos as individually tracked transfers.
  ///
  /// Returns the CDN URLs in pick order, or null when the seller backed out of
  /// a batch that had failures. Only the failed rows are re-sent on retry, so a
  /// four-photo listing with one bad photo costs one re-upload, not four.
  ///
  /// Returns an empty list when there is nothing new to send, which is the
  /// normal edit case where every photo already lives on the CDN.
  Future<List<String>?> _uploadPickedImages() async {
    if (_newImages.isEmpty) return const [];

    setState(() => _publishStage = ProductPublishStage.uploadingImages);

    final batch =
        _productService.buildImageUploadBatch(_newImages);
    _activeBatch = batch;

    while (true) {
      await batch.startAll();
      if (!mounted) {
        await batch.dispose();
        return null;
      }

      final failures = batch.failedItems.toList();
      if (failures.isEmpty) break;

      // Offer a retry per row rather than restarting the batch: the succeeded
      // photos are already stored and re-sending them is pure waste.
      final retry = await _showUploadFailures(batch);
      if (!retry || !mounted) {
        await batch.dispose();
        _activeBatch = null;
        return null;
      }
      await batch.retryFailed();
    }

    final urls = batch.succeededValues<String>().cast<String>();
    await batch.dispose();
    _activeBatch = null;
    return urls;
  }

  /// Explains what failed and why, with a retry that re-runs only those files.
  Future<bool> _showUploadFailures(TransferBatch batch) async {
    final failures = batch.failedItems.toList();
    final messenger = ScaffoldMessenger.of(context);
    final first = failures.first.progressSnapshot.failure;

    final reasons = <String>{
      for (final f in failures)
        _describeFailure(f.progressSnapshot.failure),
    };

    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cloud_off_rounded, color: Theme.of(ctx).colorScheme.error),
        title: Text(context.tr('upload_failed')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failures.length == 1
                  ? context.tr('upload_failed_one')
                  : context.tr('upload_failed_many', {'n': '${failures.length}'}),
            ),
            const SizedBox(height: Ds.sp3),
            // Name the cause. "Something went wrong" gives the seller nothing
            // to act on; these are the actual conditions they can fix.
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: Ds.sp1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.chevron_right_rounded, size: 16),
                    const SizedBox(width: Ds.sp1),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            const SizedBox(height: Ds.sp2),
            Text(
              failures.map((f) => f.label).join(', '),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          if (first == null || first.isRetryable)
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.tr('try_again')),
            ),
        ],
      ),
    );

    if (retry != true) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('upload_cancelled_notice'))),
      );
    }
    return retry == true;
  }

  /// Maps a failure to copy the seller can act on. Falls back to the network
  /// error translator for cases already carrying a localized message.
  String _describeFailure(TransferFailure? failure) {
    if (failure == null) return context.tr('upload_failed_generic');
    return switch (failure.kind) {
      TransferFailureKind.offline => context.tr('err_no_internet'),
      TransferFailureKind.interrupted => context.tr('err_upload_interrupted'),
      TransferFailureKind.cancelled => context.tr('upload_cancelled_notice'),
      TransferFailureKind.permissionDenied => context.tr('err_permission_denied_media'),
      TransferFailureKind.tooLarge => context.tr('err_file_too_large'),
      TransferFailureKind.unsupportedType => context.tr('err_unsupported_file'),
      TransferFailureKind.server => context.tr('err_server'),
      TransferFailureKind.authExpired => context.tr('err_session_expired'),
      TransferFailureKind.unreadableSource => context.tr('err_file_unreadable'),
      TransferFailureKind.unknown => context.tr('upload_failed_generic'),
    };
  }

  /// After a successful upload: switch to Home and open the new listing.
  void _openCreatedProduct(String productId) {
    final rootCtx = rootNavigatorKey.currentContext;
    if (rootCtx == null || !rootCtx.mounted) return;
    rootCtx.go(AppRoutes.home);
    // Wait one frame so Home is visible before the detail page slides in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ctx.push('${AppRoutes.productDetail}/$productId');
      }
    });
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
    // Block swipe-back loss: draft has images + long form, confirm first.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_saving) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? context.tr('update_product')
              : context.tr('sell_product'),
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        actions: [
          // Onyesho:fungua preview bila kuchapisha, ili muuzaji ajiruhusu
          // kuangalia kabla ya kutuma.
          if (!_saving)
            IconButton(
              tooltip: context.tr('preview'),
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () {
                final price =
                    double.tryParse(_priceController.text.replaceAll(',', '').trim());
                if (price == null || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('enter_valid_price'))),
                  );
                  return;
                }
                _confirmPreview(price);
              },
            ),
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? GoogleLoading(size: 20, strokeWidth: 2)
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
        child: Column(
          children: [
            // Onyesho la hatua inayoendelea. Hana spinner isiyoeleweka: muuzaji
            // anaona kama picha zinapakia au bidhaa inahifadhiwa.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: _saving
                  ? Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Ds.sp4,
                        vertical: Ds.sp2,
                      ),
                      child: Row(
                        children: [
                          const GoogleLoading(size: 14, strokeWidth: 2),
                          const SizedBox(width: Ds.sp2),
                          Expanded(
                            child: Text(
                              _publishStageLabel ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
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
                if (widget.initialMediaPaths != null && widget.initialMediaPaths!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr('media_received_banner', 'Media received — Sell on Soko Vibe'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sell on Soko Vibe',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('sell_on_soko_hint', 'Jaza maelezo ya bidhaa kisha chapisha — picha/video tayari imeambatanishwa.'),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                ],
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
                          child: GestureDetector(
                            onTap: () => _showImagePreview(0),
                            child: _coverImage(),
                          ),
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
                      tooltip: context.tr('scan_barcode'),
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
                SafeDropdownFormField<String>(
                  value: _selectedDistrict.isEmpty ? null : _selectedDistrict,
                  items: _allDistricts,
                  labelText: context.tr('district'),
                  hint: context.tr('district'),
                  itemLabel: (d) => d,
                  normalize: normalizeCategory,
                  onChanged: (value) => setState(() => _selectedDistrict = value ?? ''),
                ),
                const SizedBox(height: 12),
                SafeDropdownFormField<String>(
                  value: _selectedCategory,
                  items: _categories.map((c) => c.name).toList(),
                  labelText: context.tr('category'),
                  hint: context.tr('category'),
                  itemLabel: (name) {
                    final cat = _categories.firstWhere((c) => c.name == name, orElse: () => _categories.first);
                    return '${cat.nameSw} | ${cat.name}';
                  },
                  normalize: normalizeCategory,
                  validator: (v) => v == null ? context.tr('enter_category') : null,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedCategory = value;
                      _updateSubcategories();
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_subcategories.isNotEmpty)
                  SafeDropdownFormField<String>(
                    value: _selectedSubcategory.isNotEmpty ? _selectedSubcategory : null,
                    items: _subcategories.map((s) => s.name).toList(),
                    labelText: context.tr('subcategory'),
                    hint: context.tr('subcategory'),
                    itemLabel: (name) {
                      final sub = _subcategories.firstWhere((s) => s.name == name, orElse: () => _subcategories.first);
                      return '${sub.nameSw} | ${sub.name}';
                    },
                    normalize: normalizeCategory,
                    onChanged: (value) => setState(() => _selectedSubcategory = value ?? ''),
                  ),
                const SizedBox(height: 12),
                SafeDropdownFormField<String>(
                  value: _selectedCondition,
                  items: const ['new', 'used', 'refurbished'],
                  labelText: context.tr('condition'),
                  hint: context.tr('condition'),
                  itemLabel: (v) => context.tr(v),
                  normalize: normalizeCategory,
                  onChanged: (value) => setState(() => _selectedCondition = value ?? 'new'),
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
                                  tooltip: context.tr('remove_variant'),
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
          ],
        ),
      ),
    ),
    );
  }
}