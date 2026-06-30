import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/product_model.dart';
import '../../models/flash_sale_model.dart';
import '../../services/product_service.dart';
import '../../services/flash_sale_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class CreateFlashSaleScreen extends StatefulWidget {
  const CreateFlashSaleScreen({super.key});

  @override
  State<CreateFlashSaleScreen> createState() => _CreateFlashSaleScreenState();
}

class _CreateFlashSaleScreenState extends State<CreateFlashSaleScreen> {
  final ProductService _productService = ProductService();
  final FlashSaleService _flashSaleService = FlashSaleService();
  final _formKey = GlobalKey<FormState>();

  Product? _selectedProduct;
  double _discountPercent = 20;
  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now().add(const Duration(hours: 24));
  int _flashStock = 0;
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(body: Center(child: Text(context.tr('ingia_akaunti_kwanza'))));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('unda_flash_sale')),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Product>>(
          stream: _productService.getMyProducts(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: GoogleLoading(size: 32));
            }
            final products = snap.data ?? [];
            if (products.isEmpty) {
              return Center(
                child: Text(context.tr('haujapakia_bidhaa_bado'),
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('chagua_bidhaa'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...products.map((p) => _buildProductTile(p)),
                    if (_selectedProduct != null) ...[
                      const Divider(height: 32),
                      _buildSaleForm(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProductTile(Product product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _selectedProduct?.id == product.id
              ? Theme.of(context).colorScheme.tertiary
              : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          width: _selectedProduct?.id == product.id ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 56,
            height: 56,
            color: Theme.of(context).colorScheme.outlineVariant,
            child: product.images.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: product.images.first, fit: BoxFit.cover)
                : Icon(Icons.image, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        title: Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'TSh ${product.price.toStringAsFixed(0)} | Stock: ${product.stock}',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        trailing: Radio<String>(
          value: product.id,
          groupValue: _selectedProduct?.id,
          onChanged: (_) => setState(() {
            _selectedProduct = product;
            _flashStock = product.stock;
          }),
        ),
        onTap: () => setState(() {
          _selectedProduct = product;
          _flashStock = product.stock;
        }),
      ),
    );
  }

  Widget _buildSaleForm() {
    final nf = NumberFormat('#,###', 'en');
    final salePrice = _selectedProduct!.price * (1 - _discountPercent / 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('weka_maelezo_flash_sale'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),

        Text(context.tr('asilimia_punguzo').replaceAll('{0}', _discountPercent.toStringAsFixed(0)),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Slider(
          value: _discountPercent,
          min: 5,
          max: 70,
          divisions: 13,
          label: '${_discountPercent.toStringAsFixed(0)}%',
          activeColor: Theme.of(context).colorScheme.tertiary,
          onChanged: (v) => setState(() => _discountPercent = v),
        ),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.8)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('bei_ya_awali'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                    Text('TSh ${nf.format(_selectedProduct!.price.toInt())}',
                        style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('bei_ya_flash_sale'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                    Text('TSh ${nf.format(salePrice.toInt())}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        TextFormField(
          initialValue: _flashStock.toString(),
          decoration: InputDecoration(
            labelText: context.tr('stock_flash_sale'),
            border: OutlineInputBorder(),
            helperText: context.tr('idadi_bidhaa_flash'),
          ),
          keyboardType: TextInputType.number,
          onChanged: (v) => _flashStock = int.tryParse(v) ?? 0,
          validator: (v) {
            final val = int.tryParse(v ?? '');
            if (val == null || val <= 0) return context.tr('weka_idadi_sahihi');
            if (_selectedProduct != null && val > _selectedProduct!.stock) {
              return context.tr('hauwezi_kuweka_zaidi').replaceAll('{0}', '${_selectedProduct!.stock}');
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('muda_wa_kuanza')),
          subtitle: Text(
            DateFormat('dd/MM/yyyy HH:mm').format(_startTime),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDateTime(isStart: true),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('muda_wa_kuisha')),
          subtitle: Text(
            DateFormat('dd/MM/yyyy HH:mm').format(_endTime),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _pickDateTime(isStart: false),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isCreating ? null : _createFlashSale,
            icon: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: GoogleLoading(size: 16, strokeWidth: 2),
                  )
                : Icon(Icons.local_fire_department),
            label: Text(_isCreating ? context.tr('inaunda') : context.tr('unda_flash_sale_btn')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.tertiary,
              foregroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startTime : _endTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(isStart ? _startTime : _endTime),
    );
    if (time == null || !mounted) return;

    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startTime = picked;
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 24));
        }
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _createFlashSale() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('chagua_bidhaa_kwanza'))),
      );
      return;
    }
    if (_endTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('muda_kuisha_baadaye'))),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final salePrice =
          _selectedProduct!.price * (1 - _discountPercent / 100);

      final flashSaleId = await _flashSaleService.createFlashSale(
        productId: _selectedProduct!.id,
        productName: _selectedProduct!.name,
        productImage: _selectedProduct!.images.isNotEmpty
            ? _selectedProduct!.images.first
            : '',
        originalPrice: _selectedProduct!.price,
        salePrice: salePrice,
        discountPercent: _discountPercent,
        sellerId: user.uid,
        sellerName: user.displayName ?? '',
        sellerPhone: _selectedProduct!.sellerPhone ?? '',
        location: _selectedProduct!.location,
        stock: _flashStock,
        startTime: _startTime,
        endTime: _endTime,
      );

      if (mounted) {
        final sale = FlashSale(
          id: flashSaleId,
          productId: _selectedProduct!.id,
          productName: _selectedProduct!.name,
          productImage: _selectedProduct!.images.isNotEmpty
              ? _selectedProduct!.images.first
              : '',
          originalPrice: _selectedProduct!.price,
          salePrice: salePrice,
          discountPercent: _discountPercent,
          sellerId: user.uid,
          sellerName: user.displayName ?? '',
          sellerPhone: _selectedProduct!.sellerPhone ?? '',
          location: _selectedProduct!.location,
          stock: _flashStock,
          startTime: _startTime,
          endTime: _endTime,
        );
        _flashSaleService.notifyFlashSale(sale);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('flash_sale_imeundwa')),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        final msg = _flashSaleErrorMessage(context, e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  String _flashSaleErrorMessage(BuildContext context, Object e) {
    final raw = e.toString();
    if (raw.contains('FLASH_SALE_ALREADY_ACTIVE') ||
        raw.contains('Product already has an active flash sale')) {
      return context.tr('bidhaa_ina_flash_sale');
    }
    return context.tr('imeshindwa').replaceAll('{0}', raw);
  }
}
