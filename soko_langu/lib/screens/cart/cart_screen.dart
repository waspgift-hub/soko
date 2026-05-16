import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../models/cart_model.dart';
import '../../models/order_model.dart';
import '../../services/cart_service.dart';
import '../../services/order_service.dart';
import '../../services/user_service.dart';
import '../../services/mongike_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/verified_badge.dart';
import '../../app/routes.dart';
import '../../widgets/google_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartService _cartService = CartService();
  final OrderService _orderService = OrderService();
  final UserService _userService = UserService();
  bool _checkingOut = false;
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _checkout(List<CartItem> items, double total) async {
    if (items.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final Map<String, List<CartItem>> sellerGroups = {};
    for (var item in items) {
      sellerGroups.putIfAbsent(item.sellerId, () => []);
      sellerGroups[item.sellerId]!.add(item);
    }

    if (!mounted) return;

    final Map<String, UserProfile?> sellerProfiles = {};
    for (final sid in sellerGroups.keys) {
      sellerProfiles[sid] = await _userService.getProfile(sid);
    }

    if (!mounted) return;

    if (sellerGroups.length == 1) {
      final entry = sellerGroups.entries.first;
      final sellerId = entry.key;
      final sellerItems = entry.value;
      final sellerTotal = sellerItems.fold<double>(0, (sum, item) => sum + item.totalPrice);
      final profile = sellerProfiles[sellerId];
      _showSingleSellerPayment(sellerId, profile, sellerItems, sellerTotal, total, user);
    } else {
      _showMultiSellerPayment(sellerGroups, sellerProfiles, total, user);
    }
  }

  void _showSingleSellerPayment(String sellerId, UserProfile? profile, List<CartItem> items, double sellerTotal, double total, User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cs2 = Theme.of(context).colorScheme;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs2.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(context.tr('payment_method'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _paymentOptionCard(
                      icon: Icons.mobile_friendly,
                      title: context.tr('mongike'),
                      subtitle: context.tr('automated_payment'),
                      color: Colors.blue,
                      onTap: () {
                        Navigator.pop(ctx);
                        _payViaMongikeSingle(sellerId, profile, items, sellerTotal, user);
                      },
                    ),
                    const SizedBox(height: 12),
                    _paymentOptionCard(
                      icon: Icons.person,
                      title: context.tr('direct_transfer'),
                      subtitle: context.tr('send_to_seller_directly'),
                      color: Colors.green,
                      onTap: () {
                        Navigator.pop(ctx);
                        _payDirectSingle(sellerId, profile, items, sellerTotal);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMultiSellerPayment(Map<String, List<CartItem>> sellerGroups, Map<String, UserProfile?> sellerProfiles, double total, User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cs2 = Theme.of(context).colorScheme;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs2.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    Text(context.tr('send_payment_to_sellers'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("${context.tr('total')}: TSh ${total.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, color: Colors.blue)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: ListView(
                        children: sellerGroups.entries.map((entry) {
                          final sid = entry.key;
                          final sellerItems = entry.value;
                          final sellerTotal = sellerItems.fold<double>(0, (sum, item) => sum + item.totalPrice);
                          final profile = sellerProfiles[sid];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text('${context.tr('seller_label')}: ${profile?.displayName ?? sid}', style: TextStyle(fontWeight: FontWeight.bold, color: cs2.primary)),
                                    VerifiedBadge(tier: profile?.accountTier, size: 14),
                                  ]),
                                  const SizedBox(height: 4),
                                  ...sellerItems.map((item) => Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Text('${item.name} x${item.quantity} = TSh ${item.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)))),
                                  const SizedBox(height: 4),
                                  Text('${context.tr('subtotal')}: TSh ${sellerTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  if (profile != null && profile.phone.isNotEmpty)
                                    Text('${context.tr('phone_label')}: ${profile.phone}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)), child: Text(context.tr('send_money_instructions'), style: TextStyle(fontSize: 11, color: Colors.amber[900]), textAlign: TextAlign.center)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: cs2.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _placeOrdersDirect(sellerGroups, sellerProfiles);
                        },
                        child: Text('Place Orders (${sellerGroups.length})', style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _paymentOptionCard({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]))])), const Icon(Icons.chevron_right)])));
  }

  Future<void> _payViaMongikeSingle(String sellerId, UserProfile? profile, List<CartItem> items, double sellerTotal, User user) async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(context.tr('pay_via_mongike')), content: TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('phone'), hintText: '+255 7XX XXX XXX', prefixIcon: const Icon(Icons.phone))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))), ElevatedButton(onPressed: () { Navigator.pop(ctx); _executeMongikePayment(sellerId, profile, items, sellerTotal, user, _phoneController.text.trim()); }, child: Text(context.tr('pay_now')))]));
      return;
    }
    await _executeMongikePayment(sellerId, profile, items, sellerTotal, user, phone);
  }

  Future<void> _executeMongikePayment(String sellerId, UserProfile? profile, List<CartItem> items, double sellerTotal, User user, String phone) async {
    setState(() => _checkingOut = true);
    try {
      for (final item in items) {
        final result = await MongikeService.initiateMarketplacePayment(
          productPrice: item.totalPrice,
          productName: item.name,
          productId: item.productId,
          sellerId: sellerId,
          sellerName: profile?.displayName ?? '',
          email: user.email ?? '',
          phone: phone,
        );
        if (result == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.name}: ${context.tr('payment_failed')}')));
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green, content: Text(context.tr('mongike_prompt_sent'))));
        await _cartService.clearCart();
        await context.push(AppRoutes.orders);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${context.tr('payment_failed')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _payDirectSingle(String sellerId, UserProfile? profile, List<CartItem> items, double sellerTotal) async {
    setState(() => _checkingOut = true);
    try {
      final orderItems = items.map((item) => OrderItem(productId: item.productId, name: item.name, price: item.price, quantity: item.quantity, image: item.image)).toList();
      await _orderService.createOrder(items: orderItems, totalAmount: sellerTotal, sellerId: sellerId, paymentMethod: 'Direct (M-Pesa/Airtel)', paymentMethodName: 'Direct Transfer', paymentNumber: profile?.phone ?? '');
      await _cartService.clearCart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('1 ${context.tr('orders_placed')}')));
        await context.push(AppRoutes.orders);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${context.tr('checkout_failed')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  Future<void> _placeOrdersDirect(Map<String, List<CartItem>> sellerGroups, Map<String, UserProfile?> sellerProfiles) async {
    setState(() => _checkingOut = true);
    try {
      int count = 0;
      for (final entry in sellerGroups.entries) {
        final sid = entry.key;
        final sellerItems = entry.value;
        final sellerTotal = sellerItems.fold<double>(0, (sum, item) => sum + item.totalPrice);
        final profile = sellerProfiles[sid];
        final orderItems = sellerItems.map((item) => OrderItem(productId: item.productId, name: item.name, price: item.price, quantity: item.quantity, image: item.image)).toList();
        await _orderService.createOrder(items: orderItems, totalAmount: sellerTotal, sellerId: sid, paymentMethod: 'Direct (M-Pesa/Airtel)', paymentMethodName: 'Direct Transfer', paymentNumber: profile?.phone ?? '');
        count++;
      }
      await _cartService.clearCart();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count ${context.tr('orders_placed')}')));
        await context.push(AppRoutes.orders);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${context.tr('checkout_failed')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cartService = _cartService;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('shopping_cart'))),
      body: SafeArea(
        child: StreamBuilder<List<CartItem>>(
          stream: cartService.getCartItems(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const GoogleLoadingPage();
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)), const SizedBox(height: 16), Text(context.tr('cart_empty'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16)), const SizedBox(height: 16), ElevatedButton.icon(onPressed: () => context.push('/'), icon: const Icon(Icons.shopping_bag), label: Text(context.tr('start_shopping')))]));
            }
            return Column(children: [
              Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length, itemBuilder: (context, index) {
                final item = items[index];
                return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                  if (item.image != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: item.image!, width: 80, height: 80, fit: BoxFit.cover)) else Container(width: 80, height: 80, color: cs.surfaceContainerHighest, child: const Icon(Icons.image)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text("${context.currencySymbol()}${item.price.toStringAsFixed(0)}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      IconButton(icon: const Icon(Icons.remove, size: 18), onPressed: () => cartService.updateQuantity(item.productId, item.quantity - 1)),
                      Text("${item.quantity}"),
                      IconButton(icon: const Icon(Icons.add, size: 18), onPressed: () => cartService.updateQuantity(item.productId, item.quantity + 1)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => cartService.removeFromCart(item.productId)),
                    ]),
                  ])),
                ])));
              })),
              Container(padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16), decoration: BoxDecoration(color: cs.surface, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]), child: StreamBuilder<double>(stream: cartService.getCartTotal(), builder: (context, snapshot) {
                final total = snapshot.data ?? 0.0;
                return Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${context.tr('total')}:", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text("${context.currencySymbol()}${total.toStringAsFixed(0)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue))]),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: _checkingOut ? null : () => _checkout(items, total), child: _checkingOut ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.tr('checkout'), style: const TextStyle(color: Colors.white, fontSize: 16)))),
                ]);
              })),
            ]);
          },
        ),
      ),
    );
  }
}
