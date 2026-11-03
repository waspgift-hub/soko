import 'package:hive_flutter/hive_flutter.dart';
import '../models/cached_product.dart';
import '../models/cached_chat_room.dart';
import '../models/cached_message.dart';
import '../models/message_model.dart';
import '../models/chat_room.dart';

/// Centralised Hive initialisation and box access for offline caching.
///
/// Call [init] once during app startup (before any repository reads).
class LocalCacheService {
  LocalCacheService._();

  static const String _productBox = 'cached_products';
  static const String _roomBox = 'cached_rooms';
  static const String _messagePrefix = 'cached_messages_';

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
}
