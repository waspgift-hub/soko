import 'package:hive_flutter/hive_flutter.dart';
import '../models/cached_product.dart';
import '../models/cached_chat_room.dart';
import '../models/cached_message.dart';
import '../models/message_model.dart';
import '../models/chat_room.dart';
import '../models/order_model.dart';
import '../models/wallet_model.dart';

/// Centralised Hive initialisation and box access for offline caching.
///
/// Call [init] once during app startup (before any repository reads).
class LocalCacheService {
  LocalCacheService._();

  static const String _productBox = 'cached_products';
  static const String _roomBox = 'cached_rooms';
  static const String _messagePrefix = 'cached_messages_';
  static const String _orderBox = 'cached_orders';
  static const String _walletBox = 'cached_wallet';

  static bool _initialized = false;

  /// Open all boxes and register adapters. Idempotent — safe to call multiple times.
  static Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();
    Hive.registerAdapter(CachedProductAdapter());
    Hive.registerAdapter(CachedChatRoomAdapter());
    Hive.registerAdapter(CachedMessageAdapter());

    await Hive.openBox<CachedProduct>(_productBox);
    await Hive.openBox<CachedChatRoom>(_roomBox);
    // Orders and wallet are stored as plain Maps (API wire shape), so they
    // need no adapters — avoids codegen for the OrderData/WalletDetail DTOs.
    await Hive.openBox(_orderBox);
    await Hive.openBox(_walletBox);
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Product cache
  // ---------------------------------------------------------------------------

  static Box<CachedProduct> get _products => Hive.box<CachedProduct>(_productBox);

  /// All cached products (ordered by insertion).
  static List<CachedProduct> getCachedProducts() => _products.values.toList();

  /// Replace the entire product cache with fresh data.
  static Future<void> cacheProducts(List<CachedProduct> products) async {
    await _products.clear();
    for (final p in products) {
      await _products.put(p.id, p);
    }
  }

  /// Append a single product to the cache.
  static Future<void> cacheProduct(CachedProduct product) async {
    await _products.put(product.id, product);
  }

  /// Remove stale entries.
  static Future<void> clearProducts() async => _products.clear();

  /// Number of cached products.
  static int get productCount => _products.length;

  // ---------------------------------------------------------------------------
  // Room cache
  // ---------------------------------------------------------------------------

  static Box<CachedChatRoom> get _rooms => Hive.box<CachedChatRoom>(_roomBox);

  static List<ChatRoom> getCachedRoomsForUser(String userId) {
    return _rooms.values
        .where((r) => r.participants.contains(userId))
        .map((r) => r.toChatRoom())
        .toList();
  }

  static Future<void> cacheRooms(List<ChatRoom> rooms) async {
    await _rooms.clear();
    for (final r in rooms) {
      await _rooms.put(r.id, CachedChatRoom.fromChatRoom(r));
    }
  }

  // ---------------------------------------------------------------------------
  // Message cache
  // ---------------------------------------------------------------------------

  static Box<CachedMessage> _getMessageBox(String roomId) {
    return Hive.box<CachedMessage>('$_messagePrefix$roomId');
  }

  static Future<void> _ensureMessageBox(String roomId) async {
    if (!Hive.isBoxOpen('$_messagePrefix$roomId')) {
      await Hive.openBox<CachedMessage>('$_messagePrefix$roomId');
    }
  }

  static Future<List<Message>> getCachedMessages(String roomId) async {
    await _ensureMessageBox(roomId);
    final box = _getMessageBox(roomId);
    return box.values.map((c) => c.toMessage()).toList();
  }

  static Future<void> cacheMessages(String roomId, List<Message> msgs) async {
    await _ensureMessageBox(roomId);
    final box = _getMessageBox(roomId);
    await box.clear();
    for (final m in msgs) {
      await box.put(m.id, CachedMessage.fromMessage(roomId, m));
    }
  }

  static Future<void> cacheSingleMessage(String roomId, Message msg) async {
    await _ensureMessageBox(roomId);
    final box = _getMessageBox(roomId);
    await box.put(msg.id, CachedMessage.fromMessage(roomId, msg));
  }

  // ---------------------------------------------------------------------------
  // Order cache
  // ---------------------------------------------------------------------------

  static Box get _orders => Hive.box(_orderBox);

  /// Re-encode a cached [OrderData] into the API wire shape so it round-trips
  /// through [OrderData.fromApi]'s tolerant parser.
  static Map<String, dynamic> _orderToJson(OrderData o) => {
        'id': o.id,
        'orderNumber': o.orderNumber,
        'status': o.status,
        'productSnapshot': {
          'title': o.productName,
          'imageUrl': o.productImage,
          'unitPrice': o.productPrice,
          'quantity': o.quantity,
        },
        'shippingFee': o.shippingFee,
        'totalAmount': o.totalAmount,
        'platformCommission': o.platformCommission,
        'courierName': o.courierName,
        'trackingNumber': o.trackingNumber,
        'buyer': {'displayName': o.buyerName},
        'seller': {'storeName': o.sellerName},
        'createdAt': o.createdAt?.toIso8601String(),
        'paidAt': o.paidAt?.toIso8601String(),
        'completedAt': o.completedAt?.toIso8601String(),
        'cancelledAt': o.cancelledAt?.toIso8601String(),
      };

  static OrderData? _orderFromJson(Object? raw) {
    return raw is Map
        ? OrderData.fromApi(Map<String, dynamic>.from(raw))
        : null;
  }

  /// All cached orders (by insertion order).
  static Future<List<OrderData>> getCachedOrders() async =>
      _orders.values.map(_orderFromJson).whereType<OrderData>().toList();

  /// Replace the entire order cache with fresh data.
  static Future<void> saveOrders(List<OrderData> orders) async {
    await _orders.clear();
    for (final o in orders) {
      await _orders.put(o.id, _orderToJson(o));
    }
  }

  /// Single cached order, or null when not in cache.
  static Future<OrderData?> getCachedOrder(String id) async =>
      _orderFromJson(_orders.get(id));

  /// Upsert one order into the cache.
  static Future<void> saveOrder(OrderData order) async =>
      _orders.put(order.id, _orderToJson(order));

  /// Drop a single order (e.g. after a mutation invalidates it).
  static Future<void> invalidateOrder(String id) async => _orders.delete(id);

  // ---------------------------------------------------------------------------
  // Wallet cache
  // ---------------------------------------------------------------------------

  static Box get _wallet => Hive.box(_walletBox);

  /// Re-encode a cached [WalletDetail] into the API wire shape so it
  /// round-trips through [WalletDetail.fromApi]'s tolerant parser.
  static Map<String, dynamic> _walletToJson(WalletDetail w) => {
        'balances': {
          'available': w.available,
          'pending': w.pending,
          'frozen': w.frozen,
          'totalEarned': w.totalEarned,
          'totalWithdrawn': w.totalWithdrawn,
        },
        'ledger': [
          for (final e in w.ledger)
            {
              'id': e.id,
              'type': e.type,
              'amount': e.amount,
              'balanceAfter': e.balanceAfter,
              'referenceType': e.referenceType,
              'referenceId': e.referenceId,
              'description': e.description,
              'createdAt': e.createdAt?.toIso8601String(),
            },
        ],
      };

  static WalletDetail? _walletFromJson(Object? raw) {
    return raw is Map
        ? WalletDetail.fromApi(Map<String, dynamic>.from(raw))
        : null;
  }

  /// Cached wallet snapshot, or null when never cached.
  static Future<WalletDetail?> getCachedWallet() async =>
      _walletFromJson(_wallet.isEmpty ? null : _wallet.values.first);

  /// Replace the wallet snapshot cache.
  static Future<void> saveWallet(WalletDetail wallet) async {
    await _wallet.clear();
    await _wallet.put('current', _walletToJson(wallet));
  }

  /// Drop the wallet cache (e.g. after a balance mutation).
  static Future<void> invalidateWallet() async => _wallet.clear();
}
