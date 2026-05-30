import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/cart_model.dart';

class CartService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference _cartRef() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not logged in');
    return _db.collection('users').doc(uid).collection('cart');
  }

  Stream<List<CartItem>> getCartStream() {
    return _cartRef().snapshots().map((snap) =>
        snap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return null;
          return CartItem.fromMap({'id': doc.id, ...data});
        }).whereType<CartItem>().toList());
  }

  Future<int> getCartCount() async {
    try {
      final snap = await _cartRef().get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> addToCart(CartItem item) async {
    final ref = _cartRef().doc(item.productId);
    final existing = await ref.get();
    if (existing.exists) {
      final data = existing.data() as Map<String, dynamic>;
      final currentQty = data['quantity'] as int? ?? 0;
      await ref.update({'quantity': currentQty + 1});
    } else {
      await ref.set(item.toMap());
    }
  }

  Future<void> updateQuantity(String productId, int quantity) async {
    if (quantity <= 0) {
      await removeFromCart(productId);
    } else {
      await _cartRef().doc(productId).update({'quantity': quantity});
    }
  }

  Future<void> removeFromCart(String productId) async {
    await _cartRef().doc(productId).delete();
  }

  Future<void> clearCart() async {
    final snap = await _cartRef().get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
