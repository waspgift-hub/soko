import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/order_model.dart';
import 'notification_service.dart';
import '../utils/network_error.dart';

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notif = NotificationService();

  Future<String> createOrder({
    required List<OrderItem> items,
    required double totalAmount,
    required String sellerId,
    String? shippingAddress,
    String? paymentMethod,
    String? paymentMethodName,
    String? paymentNumber,
    String? sellerName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw NetworkError(
        message: 'User not logged in',
        userMessage: 'Please log in to continue.',
      );

      final docRef = await _db.collection("orders").add({
        'buyerId': user.uid,
        'buyerName': user.displayName ?? user.email ?? 'Anonymous',
        'sellerId': sellerId,
        'items': items.map((item) => item.toMap()).toList(),
        'totalAmount': totalAmount,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'shippingAddress': shippingAddress,
        'paymentMethod': paymentMethod,
        'paymentMethodName': paymentMethodName,
        'paymentNumber': paymentNumber,
        'trackingNumber': null,
      });

      _notif.sendNotification(
        userId: sellerId,
        title: 'New Order!',
        body:
            '${user.displayName ?? "A buyer"} placed an order of TZS $totalAmount',
      );

      return docRef.id;
    } catch (e) {
      throw NetworkError(
          message: "Failed to create order: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Stream<List<Order>> getMyOrders() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection("orders")
        .where("buyerId", isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final orders = snapshot.docs
              .map((doc) => Order.fromFirestore(doc))
              .toList();
          orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return orders;
        });
  }

  Stream<List<Order>> getReceivedOrders() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection("orders")
        .where("sellerId", isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final orders = snapshot.docs
              .map((doc) => Order.fromFirestore(doc))
              .toList();
          orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return orders;
        });
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    try {
      await _db.collection("orders").doc(orderId).update({
        'status': newStatus.toString().split('.').last,
      });

      final order = await getOrderById(orderId);
      if (order != null) {
        _notif.sendNotification(
          userId: order.buyerId,
          title: 'Order ${newStatus.toString().split('.').last}',
          body:
              'Your order #${orderId.substring(0, 8)} is now ${newStatus.toString().split('.').last}',
        );
      }
    } catch (e) {
      throw NetworkError(
          message: "Failed to update order status: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<void> cancelOrder(String orderId) async {
    await updateOrderStatus(orderId, OrderStatus.cancelled);
  }

  Future<Order?> getOrderById(String orderId) async {
    try {
      final doc = await _db.collection("orders").doc(orderId).get();
      if (doc.exists) {
        return Order.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw NetworkError(
          message: "Failed to get order: $e",
          userMessage: translateError(e),
          originalError: e,
        );
    }
  }

  Future<void> confirmDelivery(String orderId) async {
    final user = _auth.currentUser;
    if (user == null) throw NetworkError(
      message: 'Not logged in',
      userMessage: 'Tafadhali ingia kwanza.',
    );

    final doc = await _db.collection('orders').doc(orderId).get();
    if (!doc.exists) throw NetworkError(
      message: 'Order not found',
      userMessage: 'Agizo halipatikani.',
    );

    final data = doc.data()!;
    if (data['buyerId'] != user.uid) throw NetworkError(
      message: 'Not the buyer',
      userMessage: 'Wewe si mnunuzi wa agizo hili.',
    );

    final status = data['status'] ?? 'pending';
    if (status != 'shipped' && status != 'confirmed') throw NetworkError(
      message: 'Invalid status',
      userMessage: 'Agizo halijatumwa bado.',
    );

    if (data['escrowReleased'] == true) throw NetworkError(
      message: 'Already released',
      userMessage: 'Malipo tayari yametolewa.',
    );

    await _db.collection('orders').doc(orderId).update({
      'status': 'delivered',
      'escrowReleased': true,
      'escrowReleasedAt': FieldValue.serverTimestamp(),
    });

    final sellerId = data['sellerId'] as String;
    final totalAmount = (data['totalAmount'] ?? 0).toDouble();

    await _db.collection('users').doc(sellerId).update({
      'sellerBalance': FieldValue.increment(totalAmount),
    });

    await _db.collection('revenue_transactions').add({
      'userId': sellerId,
      'type': 'sale',
      'amount': totalAmount,
      'orderId': orderId,
      'description': 'Sale: TZS ${totalAmount.toStringAsFixed(0)}',
      'timestamp': FieldValue.serverTimestamp(),
    });

    _notif.sendNotification(
      userId: sellerId,
      title: 'Malipo Yamefikishwa!',
      body: 'Mnunuzi amethibitisha kupokea agizo #$orderId. TZS ${totalAmount.toStringAsFixed(0)} imeongezwa kwenye salio lako.',
    );
  }

  Stream<List<Order>> getDeliverableOrders() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db.collection('orders')
        .where('buyerId', isEqualTo: user.uid)
        .where('status', whereIn: ['shipped', 'confirmed'])
        .snapshots()
        .map((snap) => snap.docs.map((d) => Order.fromFirestore(d)).toList());
  }
}
