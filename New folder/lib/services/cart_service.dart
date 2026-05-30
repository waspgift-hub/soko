import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/cart_model.dart';
import '../utils/network_error.dart';

class CartService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  // =========================
  // 🛒 GET CART ITEMS
  // =========================
  Stream<List<CartItem>> getCartItems() {
    if (_userId == null) return Stream.value([]);

    return _db
        .collection("carts")
        .doc(_userId)
        .collection("items")
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => CartItem.fromMap(doc.data())).toList(),
        );
  }

  // =========================
  // ➕ ADD TO CART
  // =========================
  Future<void> addToCart(CartItem item) async {
    if (_userId == null) throw NetworkError(
        message: 'User not logged in',
        userMessage: 'Please log in to continue.',
      );

    try {
      final docRef = _db
          .collection("carts")
          .doc(_userId)
          .collection("items")
          .doc(item.productId);

      final existing = await docRef.get();
      if (existing.exists) {
        // Update quantity if item already in cart
        await docRef.update({'quantity': FieldValue.increment(item.quantity)});
      } else {
        await docRef.set(item.toMap());
      }
    } catch (e) {
      throw NetworkError(
          message: "Failed to add to cart: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  // =========================
  // 🔄 UPDATE QUANTITY
  // =========================
  Future<void> updateQuantity(String productId, int quantity) async {
    if (_userId == null) throw NetworkError(
        message: 'User not logged in',
        userMessage: 'Please log in to continue.',
      );

    try {
      if (quantity <= 0) {
        await removeFromCart(productId);
        return;
      }

      await _db
          .collection("carts")
          .doc(_userId)
          .collection("items")
          .doc(productId)
          .update({'quantity': quantity});
    } catch (e) {
      throw NetworkError(
          message: "Failed to update quantity: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  // =========================
  // 🗑️ REMOVE FROM CART
  // =========================
  Future<void> removeFromCart(String productId) async {
    if (_userId == null) throw NetworkError(
        message: 'User not logged in',
        userMessage: 'Please log in to continue.',
      );

    try {
      await _db
          .collection("carts")
          .doc(_userId)
          .collection("items")
          .doc(productId)
          .delete();
    } catch (e) {
      throw NetworkError(
          message: "Failed to remove from cart: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  // =========================
  // 🧹 CLEAR CART
  // =========================
  Future<void> clearCart() async {
    if (_userId == null) throw NetworkError(
        message: 'User not logged in',
        userMessage: 'Please log in to continue.',
      );

    try {
      final items = await _db
          .collection("carts")
          .doc(_userId)
          .collection("items")
          .get();

      final batch = _db.batch();
      for (var doc in items.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      throw NetworkError(
          message: "Failed to clear cart: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  // =========================
  // 💰 GET CART TOTAL
  // =========================
  Stream<double> getCartTotal() {
    return getCartItems().map(
      (items) => items.fold(0, (total, item) => total + item.totalPrice),
    );
  }
}
