import 'order_statuses.dart';

/// Postgres order DTO from `/api/v1/orders`.
///
/// Phase B/C bridge: mirrors the server's v2 order shape (money in BigInt is
/// serialized as JSON numbers on the wire). Parsing is tolerant because the
/// server emits two snapshot shapes today — the v1 `createOrder` snapshot
/// (`title`/`imageUrl`/`price`) versus the legacy-shop snapshot
/// (`name`/`image`/`unitPrice`).
class OrderData {
  final String id;
  final String orderNumber;
  final String status;
  final String productName;
  final String productImage;
  final int productPrice;
  final int shippingFee;
  final int totalAmount;
  final int platformCommission;
  final int quantity;
  final String? courierName;
  final String? trackingNumber;
  final String buyerName;
  final String sellerName;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  const OrderData({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.productName,
    required this.productImage,
    required this.productPrice,
    required this.shippingFee,
    required this.totalAmount,
    required this.platformCommission,
    required this.quantity,
    this.courierName,
    this.trackingNumber,
    this.buyerName = '',
    this.sellerName = '',
    this.createdAt,
    this.paidAt,
    this.completedAt,
    this.cancelledAt,
  });

  factory OrderData.fromApi(Map<String, dynamic> json) {
    final snapshot =
        json['productSnapshot'] is Map<String, dynamic>
            ? json['productSnapshot'] as Map<String, dynamic>
            : const <String, dynamic>{};
    final items =
        json['items'] is List
            ? (json['items'] as List).whereType<Map<String, dynamic>>().toList()
            : const <Map<String, dynamic>>[];

    final buyer =
        json['buyer'] is Map<String, dynamic>
            ? json['buyer'] as Map<String, dynamic>
            : const <String, dynamic>{};
    final seller =
        json['seller'] is Map<String, dynamic>
            ? json['seller'] as Map<String, dynamic>
            : const <String, dynamic>{};

    final quantity = _firstInt(items, 'quantity') ??
        _intOf(snapshot['quantity']) ??
        1;

    return OrderData(
      id: json['id'] as String? ?? '',
      orderNumber: _strOf(json['orderNumber']) ?? _strOf(json['id']) ?? '',
      status: _strOf(json['status']) ?? '',
      productName: _strOf(snapshot['title']) ?? _strOf(snapshot['name']) ?? '',
      productImage: _strOf(snapshot['imageUrl']) ?? _strOf(snapshot['image']) ?? '',
      productPrice: _intOf(snapshot['unitPrice']) ??
          _intOf(snapshot['price']) ??
          _intOf(json['productPrice']) ??
          0,
      shippingFee: _intOf(json['shippingFee']) ?? 0,
      totalAmount: _intOf(json['totalAmount']) ?? 0,
      platformCommission: _intOf(json['platformCommission']) ?? 0,
      quantity: quantity,
      courierName: _strOf(json['courierName']),
      trackingNumber: _strOf(json['trackingNumber']),
      buyerName: _strOf(buyer['displayName']) ?? _strOf(buyer['name']) ?? '',
      sellerName: _strOf(seller['storeName']) ?? _strOf(seller['name']) ?? '',
      createdAt: _dateOf(json['createdAt']),
      paidAt: _dateOf(json['paidAt']),
      completedAt: _dateOf(json['completedAt']),
      cancelledAt: _dateOf(json['cancelledAt']),
    );
  }

  /// Firestore document snapshot → [OrderData].
  /// Maps both [orders] and [transactions] collection fields, merging payment/
  /// escrow state from the transactions doc when available, otherwise falls back
  /// to the orders doc metadata.
  factory OrderData.fromFirestore(String docId, Map<String, dynamic> data) {
    final order = data['order'] is Map
        ? Map<String, dynamic>.from(data['order'] as Map)
        : <String, dynamic>{};
    final tx = data['transaction'] is Map
        ? Map<String, dynamic>.from(data['transaction'] as Map)
        : <String, dynamic>{};

    // Money stays in whole TZS as int. Truncating through double here would
    // lose shillings on large orders and disagree with the server total.
    int money(Object? v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.round();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    final productPrice = money(order['productPrice'] ?? tx['productPrice']);
    final createdAt = order['createdAt'] ?? tx['createdAt'];

    return OrderData(
      id: docId,
      orderNumber: (order['orderNumber'] ?? tx['orderNumber'] ?? docId).toString(),
      // Normalise so a legacy alias and its canonical form cannot render as
      // two different states on two screens.
      status: canonicalStatusOf(
        (order['status'] ?? tx['status'] ?? 'pending').toString(),
      ),
      productName: (order['productName'] ?? tx['productName'] ?? '').toString(),
      productImage: (order['productImage'] ?? tx['productImage'] ?? '').toString(),
      productPrice: productPrice,
      shippingFee: money(tx['shippingCost'] ?? order['shippingCost']),
      totalAmount: money(tx['totalAmount'] ?? order['totalAmount'], productPrice),
      platformCommission: money(tx['platformFee'] ?? order['platformFee']),
      quantity: money(order['quantity'] ?? tx['quantity'], 1),
      courierName: tx['courierName']?.toString(),
      trackingNumber: tx['trackingNumber']?.toString(),
      buyerName: (order['buyerName'] ?? tx['buyerName'] ?? '').toString(),
      sellerName: (order['sellerName'] ?? tx['sellerName'] ?? '').toString(),
      createdAt: _dateOf(createdAt),
      paidAt: _dateOf(tx['paidAt']),
      completedAt: _dateOf(tx['completedAt']),
      cancelledAt: _dateOf(order['cancelledAt']),
    );
  }

  static String? _strOf(dynamic v) => v is String ? v : null;

  static int? _intOf(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static int? _firstInt(List<Map<String, dynamic>> maps, String key) {
    for (final m in maps) {
      final v = _intOf(m[key]);
      if (v != null) return v;
    }
    return null;
  }

  static DateTime? _dateOf(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    // Firestore Timestamp. Duck-typed through toDate() rather than importing
    // cloud_firestore, which keeps this model unit-testable without Firebase.
    try {
      final d = v.toDate();
      if (d is DateTime) return d.toLocal();
    } catch (_) {}
    final parsed = DateTime.tryParse('$v');
    return parsed?.toLocal();
  }
}