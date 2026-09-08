import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/cart_item.dart';
import '../../services/cart_service.dart';
import '../../services/product_service.dart';
import '../../extensions/context_tr.dart';
import '../../app/routes.dart';
import '../../widgets/ds/ds.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/soko_widgets.dart';

/// Buyer's holding tray: items grouped by seller, quantity edits clamped to
/// stock, live totals. Each line opens the existing single-product
/// CheckoutScreen so the backend stays the source of truth for orders.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartService _cart = CartService();
  final ProductService _products = ProductService();

  Future<void> _checkoutItem(CartItem item) async {
    if (!mounted) return;
    if (item.productId.isEmpty) return;
    try {
      final product = await _products.getProductById(item.productId);
      if (!mounted) return;
      if (product == null) {
        _toast(context.tr('out_of_stock', 'Product no longer available'));
        return;
      }
      if (!product.isActive || product.stock <= 0) {
        _toast(context.tr('out_of_stock', 'Out of stock'));
        return;
      }
      context.push(AppRoutes.checkout, extra: {
        'product': product,
        'quantity': item.quantity,
        'variantId': item.variantId,
        'unitPrice': item.unitPrice,
      });
    } catch (_) {
      if (mounted) {
        _toast(context.tr('failed_to_create_order', 'Failed to create order'));
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    SokoSnackbar.info(context, msg);
  }

  void _confirmClear() {
    SokoDialog.show(
      context,
      variant: SokoDialogVariant.danger,
      icon: Icons.delete_sweep_outlined,
      title: context.tr('clear_cart', 'Clear Cart'),
      message: context.tr('confirm_clear_cart', 'Remove all items from your cart?'),
      confirmLabel: context.tr('clear_cart', 'Clear'),
      cancelLabel: context.tr('cancel', 'Cancel'),
    ).then((confirmed) {
      if (confirmed) _cart.clearAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('cart_title', 'Cart')),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: StreamBuilder<List<CartItem>>(
        stream: _cart.watch(),
        builder: (context, snap) {
          final items = snap.data ?? _cart.items;
          if (items.isEmpty) return _emptyState(cs);
          final groups = _cart.grouped();
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.s3),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final entry in groups.entries) ...[
                  _SellerGroup(
                    sellerName: entry.value.first.sellerName,
                    items: entry.value,
                    onQtyChanged: (item, qty) =>
                        _cart.updateQty(item.productId, item.variantId, qty),
                    onRemove: (item) =>
                        _cart.remove(item.productId, item.variantId),
                    onOrder: (item) => _checkoutItem(item),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                ],
                const SizedBox(height: AppSpacing.s3),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: StreamBuilder<List<CartItem>>(
        stream: _cart.watch(),
        builder: (context, snap) {
          final items = snap.data ?? _cart.items;
          if (items.isEmpty) return const SizedBox.shrink();
          final count = items.fold<int>(0, (sum, e) => sum + e.quantity);
          return Container(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s3,
              AppSpacing.s2,
              AppSpacing.s3,
              MediaQuery.of(context).padding.bottom + AppSpacing.s2,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
            ),
            child: CartSummary(
              subtotal: _cart.subtotal,
              note: '$count ${context.tr('items', 'items')}',
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined,
              size: 72, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: AppSpacing.s3),
          Text(
            context.tr('empty_cart', 'Empty Cart'),
            style: AppTypography.screenTitle(cs.onSurface),
          ),
          const SizedBox(height: AppSpacing.s2),
          DsButton(
            label: context.tr('continue_shopping', 'Continue Shopping'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _SellerGroup extends StatelessWidget {
  final String sellerName;
  final List<CartItem> items;
  final void Function(CartItem item, int qty) onQtyChanged;
  final void Function(CartItem item) onRemove;
  final void Function(CartItem item) onOrder;

  const _SellerGroup({
    required this.sellerName,
    required this.items,
    required this.onQtyChanged,
    required this.onRemove,
    required this.onOrder,
  });

  double get _subtotal =>
      items.fold(0.0, (sum, e) => sum + e.unitPrice * e.quantity);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.s1),
              Expanded(
                child: Text(
                  sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: DsDivider(),
          ),
          for (var i = 0; i < items.length; i++) ...[
            _CartLine(
              item: items[i],
              onQtyChanged: (qty) => onQtyChanged(items[i], qty),
              onRemove: () => onRemove(items[i]),
              onOrder: () => onOrder(items[i]),
            ),
            if (i < items.length - 1)
              const SizedBox(height: AppSpacing.s2),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: DsDivider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(context.tr('subtotal', 'Subtotal'),
                  style: AppTypography.timeIndicator(cs.onSurfaceVariant)),
              DsPrice(price: _subtotal),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  final CartItem item;
  final void Function(int qty) onQtyChanged;
  final VoidCallback onRemove;
  final VoidCallback onOrder;

  const _CartLine({
    required this.item,
    required this.onQtyChanged,
    required this.onRemove,
    required this.onOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CartItemTile(
          item: item,
          onQuantityChanged: (qty) => onQtyChanged(qty),
          onDelete: onRemove,
        ),
        const SizedBox(height: AppSpacing.s2),
        Align(
          alignment: Alignment.centerRight,
          child: DsButton(
            label: context.tr('order_now', 'Order Now'),
            variant: DsButtonVariant.secondary,
            height: 34,
            fullWidth: false,
            onPressed: onOrder,
          ),
        ),
      ],
    );
  }
}