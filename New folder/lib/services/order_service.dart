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

      final productNames = items.map((i) => i.name).join(', ');
      final isMongike = paymentMethod == 'Mongike';

      final docRef = await _db.collection("orders").add({
        'buyerId': user.uid,
        'buyerName': user.displayName ?? user.email ?? 'Anonymous',
        'sellerId': sellerId,
        'items': items.map((item) => item.toMap()).toList(),
        'totalAmount': totalAmount,
        'status': 'pending',
        'paymentStatus': isMongike ? 'pending_payment' : 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'shippingAddress': shippingAddress,
        'paymentMethod': paymentMethod,
        'paymentMethodName': paymentMethodName,
        'paymentNumber': paymentNumber,
        'trackingNumber': null,
      });

      _notif.sendNotification(
        userId: sellerId,
        title: '🛒 Agizo Jipya!',
        body: '${user.displayName ?? "Mnunuzi"} ameorder: $productNames — TSh ${totalAmount.toStringAsFixed(0)}${isMongike ? ' (Mongike)' : ''}',
        data: {
          'type': 'order',
          'orderId': docRef.id,
          'buyerId': user.uid,
          'buyerName': user.displayName ?? user.email ?? 'Mnunuzi',
          'productNames': productNames,
          'totalAmount': totalAmount.toStringAsFixed(0),
          'paymentMethod': paymentMethod ?? 'Direct',
        },
      );

      _notif.sendNotification(
        userId: user.uid,
        title: '✅ Order Yako Imeundwa!',
        body: 'Agizo #${docRef.id} limeundwa. ${isMongike ? 'Malipo yanafanywa kupitia Mongike.' : 'Tafadhali lipa kwa muuzaji.'}',
        data: {
          'type': 'order',
          'orderId': docRef.id,
          'productNames': productNames,
          'totalAmount': totalAmount.toStringAsFixed(0),
        },
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
      final order = await getOrderById(orderId);
      if (order == null) throw NetworkError(
        message: 'Order not found',
        userMessage: 'Agizo halipatikani.',
      );

      await _db.collection("orders").doc(orderId).update({
        'status': newStatus.toString().split('.').last,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final statusLabel = newStatus.toString().split('.').last;
      final statusEmoji = {
        'confirmed': '✅',
        'processing': '📦',
        'shipped': '🚚',
        'delivered': '🎉',
        'cancelled': '❌',
      }[statusLabel] ?? '📋';

      _notif.sendNotification(
        userId: order.buyerId,
        title: '$statusEmoji Order $statusLabel',
        body: 'Agizo lako #${orderId.substring(0, 8)} sasa ni $statusLabel. ${order.items.map((i) => i.name).join(', ')}',
        data: {
          'type': 'order',
          'orderId': orderId,
          'status': statusLabel,
          'productNames': order.items.map((i) => i.name).join(', '),
        },
      );

      if (newStatus == OrderStatus.confirmed) {
        _notif.sendNotification(
          userId: order.sellerId,
          title: '💰 Malipo Yamepokelewa',
          body: 'Umetangaza kupokea malipo ya agizo #${orderId.substring(0, 8)}. Sasa unaweza kutuma bidhaa.',
          data: {
            'type': 'order',
            'orderId': orderId,
            'status': 'confirmed',
          },
        );
      }

      if (newStatus == OrderStatus.shipped) {
        _notif.sendNotification(
          userId: order.buyerId,
          title: '🚚 Bidhaa Imetumwa!',
          body: 'Muuzaji ametuma bidhaa yako #${orderId.substring(0, 8)}. Subiri kupokea.',
          data: {
            'type': 'order',
            'orderId': orderId,
            'status': 'shipped',
          },
        );
      }

      if (newStatus == OrderStatus.cancelled) {
        _notif.sendNotification(
          userId: order.sellerId,
          title: '❌ Order Imeghairiwa',
          body: 'Agizo #${orderId.substring(0, 8)} limeghairiwa.',
          data: {
            'type': 'order',
            'orderId': orderId,
            'status': 'cancelled',
          },
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

    final totalAmount = (data['totalAmount'] ?? 0).toDouble();
    final paymentMethod = data['paymentMethod'] ?? 'Direct';
    final isMongike = paymentMethod == 'Mongike';

    await _db.collection('orders').doc(orderId).update({
      'status': 'delivered',
      'escrowReleased': true,
      'escrowReleasedAt': FieldValue.serverTimestamp(),
      'deliveredAt': FieldValue.serverTimestamp(),
    });

    final sellerId = data['sellerId'] as String;

    if (isMongike) {
      await _db.collection('users').doc(sellerId).update({
        'sellerBalance': FieldValue.increment(totalAmount),
        'mongikeWalletBalance': FieldValue.increment(totalAmount),
      });

      await _db.collection('mongike_transactions').add({
        'orderId': orderId,
        'sellerId': sellerId,
        'amount': totalAmount,
        'commission': totalAmount * 0.05,
        'sellerReceives': totalAmount * 0.95,
        'type': 'flash_sale_credit',
        'status': 'credited_to_wallet',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _notif.sendNotification(
        userId: sellerId,
        title: '💰 Malipo Yamefikishwa (Mongike)!',
        body: 'Mnunuzi amethibitisha kupokea agizo #$orderId. TZS ${totalAmount.toStringAsFixed(0)} imeongezwa kwenye Mongike Wallet yako. Commission 5% imekatwa.',
      );

      _notif.sendNotification(
        userId: user.uid,
        title: '🎉 Delivery Imethibitishwa!',
        body: 'Umethibitisha kupokea bidhaa. Malipo yametolewa kwa muuzaji kupitia Mongike.',
      );
    } else {
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

    _notif.sendNotification(
      userId: user.uid,
      title: '🌟 Tathmini Bidhaa!',
      body: 'Bidhaa yako imefika. Tafadhali tathmini ili kusaidia wengine.',
      data: {
        'type': 'review',
        'orderId': orderId,
      },
    );
  }

  Future<void> confirmMongikePayment(String orderId) async {
    final doc = await _db.collection('orders').doc(orderId).get();
    if (!doc.exists) throw NetworkError(
      message: 'Order not found',
      userMessage: 'Agizo halipatikani.',
    );

    final data = doc.data()!;
    if (data['paymentMethod'] != 'Mongike') throw NetworkError(
      message: 'Not a Mongike payment',
      userMessage: 'Hii si order ya Mongike.',
    );

    await _db.collection('orders').doc(orderId).update({
      'paymentStatus': 'paid',
      'status': 'confirmed',
      'mongikePaidAt': FieldValue.serverTimestamp(),
    });

    final sellerId = data['sellerId'] as String;
    final buyerId = data['buyerId'] as String;
    final totalAmount = (data['totalAmount'] ?? 0).toDouble();

    _notif.sendNotification(
      userId: sellerId,
      title: '💳 Malipo Yamepokelewa (Mongike)',
      body: 'Mnunuzi amelipa kupitia Mongike. Agizo #${orderId.substring(0, 8)} sasa limeconfirm. TSh ${totalAmount.toStringAsFixed(0)}',
      data: {
        'type': 'order',
        'orderId': orderId,
        'status': 'confirmed',
      },
    );

    _notif.sendNotification(
      userId: buyerId,
      title: '✅ Mongike Payment Confirmed',
      body: 'Malipo yako ya Mongike yamethibitishwa. Muuzaji sasa anatumia bidhaa yako.',
      data: {
        'type': 'order',
        'orderId': orderId,
        'status': 'confirmed',
      },
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
