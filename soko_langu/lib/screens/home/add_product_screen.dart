import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/product_service.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../services/category_service.dart';
import '../../extensions/context_tr.dart';

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
  final _locationController = TextEditingController(text: 'Tanzania');

  String _selectedCategory = 'Electronics';
  String _selectedSubcategory = '';
  String _selectedCondition = 'new';
  List<String> _subcategories = [];
  List<XFile> _newImages = [];
  List<String> _existingImages = [];
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
    if (p.brand != null) _brandController.text = p.brand!;
    if (p.location.isNotEmpty) _locationController.text = p.location;
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
    final category = _categories.firstWhere(
      (cat) => cat.name == _selectedCategory,
      orElse: () => _categories.first,
    );
    setState(() {
      _subcategories = category.subcategories.map((s) => s.name).toList();
      if (_subcategories.isNotEmpty &&
          !_subcategories.contains(_selectedSubcategory)) {
        _selectedSubcategory = _subcategories.first;
      }
    });
  }

  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() => _newImages.addAll(images));
    }
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImages.removeAt(index));
  }

  void _removeNewImage(int index) {
    setState(() => _newImages.removeAt(index));
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

    setState(() => _saving = true);
    try {
      final variantData = _buildVariantData();
      if (_isEditing) {
        await _productService.updateProduct(
          productId: widget.product!.id,
          name: _nameController.text,
          description: _descriptionController.text,
          price: double.parse(_priceController.text),
          category: _selectedCategory,
          subcategory: _selectedSubcategory,
          stock: int.parse(_stockController.text),
          isWholesale: _isWholesale,
          variants: variantData.isNotEmpty ? variantData : null,
          brand: _brandController.text.isNotEmpty
              ? _brandController.text
              : null,
          condition: _selectedCondition,
          existingImages: _existingImages.isNotEmpty ? _existingImages : null,
          newImages: _newImages.isNotEmpty ? _newImages : null,
        );
      } else {
        await _productService.addProduct(
          name: _nameController.text,
          description: _descriptionController.text,
          price: double.parse(_priceController.text),
          category: _selectedCategory,
          subcategory: _selectedSubcategory,
          currency: 'TZS',
          stock: int.parse(_stockController.text),
          imageFiles: _newImages,
          isWholesale: _isWholesale,
          variants: variantData.isNotEmpty ? variantData : null,
          brand: _brandController.text.isNotEmpty
              ? _brandController.text
              : null,
          condition: _selectedCondition,
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
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _isEditing
              ? context.tr('update_product')
              : context.tr('sell_product'),
          style: const TextStyle(color: Colors.green),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.green,
                    ),
                  )
                : Text(
                    _isEditing
                        ? context.tr('update_product').toUpperCase()
                        : context.tr('sell_product').toUpperCase(),
                    style: const TextStyle(color: Colors.green),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('product_images'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                        width: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.add_a_photo,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    ..._existingImages.map(
                      (url) => Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: NetworkImage(url),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _removeExistingImage(
                                _existingImages.indexOf(url),
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._newImages.map(
                      (file) => Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: FileImage(File(file.path)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () =>
                                  _removeNewImage(_newImages.indexOf(file)),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.tr('product_name'),
                  border: const OutlineInputBorder(),
                  labelStyle: const TextStyle(color: Colors.green),
                ),
                validator: (v) => v!.isEmpty ? context.tr('required') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: context.tr('description'),
                  border: const OutlineInputBorder(),
                  labelStyle: const TextStyle(color: Colors.green),
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
                        labelStyle: const TextStyle(color: Colors.green),
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
                        labelStyle: const TextStyle(color: Colors.green),
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
                  labelStyle: const TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: context.tr('location'),
                  border: const OutlineInputBorder(),
                  labelStyle: const TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: context.tr('category'),
                  border: const OutlineInputBorder(),
                  labelStyle: const TextStyle(color: Colors.green),
                ),
                items: _categories
                    .map(
                      (cat) => DropdownMenuItem(
                        value: cat.name,
                        child: Text(cat.nameSw),
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
                  initialValue: _selectedSubcategory.isNotEmpty
                      ? _selectedSubcategory
                      : null,
                  decoration: InputDecoration(
                    labelText: context.tr('subcategory'),
                    border: const OutlineInputBorder(),
                    labelStyle: const TextStyle(color: Colors.green),
                  ),
                  items: _subcategories
                      .map(
                        (sub) => DropdownMenuItem(value: sub, child: Text(sub)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedSubcategory = value!),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedCondition,
                decoration: InputDecoration(
                  labelText: context.tr('condition'),
                  border: const OutlineInputBorder(),
                  labelStyle: const TextStyle(color: Colors.green),
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
              SwitchListTile(
                title: Text(
                  context.tr('wholesale'),
                  style: const TextStyle(color: Colors.green),
                ),
                value: _isWholesale,
                onChanged: (value) => setState(() => _isWholesale = value),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Variants",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Add"),
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
                                decoration: const InputDecoration(
                                  labelText: "Name (e.g. Size, Color)",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _removeVariant(i),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: v.valueCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Value (e.g. Large, Red)",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: v.priceCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Price \u00B1",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: v.stockCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Stock",
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
    );
  }
}
