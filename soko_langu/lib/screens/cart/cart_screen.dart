import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/cart_model.dart';
import '../../services/cart_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('Ingia akaunti yako kuona cart', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => context.push(AppRoutes.login), child: const Text('Ingia')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: _CartBody(),
    );
  }
}

class _CartBody extends StatefulWidget {
  @override
  State<_CartBody> createState() => _CartBodyState();
}

class _CartBodyState extends State<_CartBody> {
  final CartService _cartService = CartService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CartItem>>(
      stream: _cartService.getCartStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: GoogleLoading(size: 32));
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('Cart yako iko tupu', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('Ongeza bidhaa unazotaka kununua', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
              ],
            ),
          );
        }

        final total = items.fold<double>(0, (sum, item) => sum + item.totalPrice);

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) => _buildCartItemCard(items[i]),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Jumla', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          Text(context.formatPrice(total.toDouble()),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F))),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push(AppRoutes.checkout, extra: items),
                        icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                        label: const Text('Checkout'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCartItemCard(CartItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 70, height: 70, color: Colors.grey[200],
                child: item.image.isNotEmpty
                    ? CachedNetworkImage(imageUrl: item.image, fit: BoxFit.cover)
                    : const Icon(Icons.image, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(context.formatPrice(item.price), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _qtyButton(Icons.remove, () => _cartService.updateQuantity(item.productId, item.quantity - 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      _qtyButton(Icons.add, () => _cartService.updateQuantity(item.productId, item.quantity + 1)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => _cartService.removeFromCart(item.productId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: Colors.grey[700]),
      ),
    );
  }
}
