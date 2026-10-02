import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/category_model.dart';
import 'api_config.dart';
import 'product_api.dart';

class CategoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ProductApiClient _api = ProductApiClient();
  List<Category>? _cached;
  Stream<List<Category>>? _cachedStream;

  // Callers write `CategoryService().watchCategories()` inside a
  // `StreamBuilder.stream:`, so every build used to construct a new instance.
  // The per-instance `_cachedStream` cache therefore never hit: each rebuild
  // opened a fresh Firestore listener on `categories` (or, on the HTTP path, a
  // fresh `Stream.fromFuture` and therefore a fresh categories request). One
  // shared instance plus one broadcast stream fixes every call site at once.
  static CategoryService? _shared;

  factory CategoryService() => _shared ??= CategoryService._internal();

  CategoryService._internal();

  // =========================
  // SHIPPED TREE (static, synchronous)
  // =========================
  // The browsable roots, in taxonomy order, without the hidden legacy catch-all.
  //
  // Static and synchronous on purpose: the category tree is compiled into the
  // app, so every screen can render it on its first frame. The remote stream in
  // [watchCategories] is a refresh path layered on top, not a prerequisite — an
  // async-only API is what previously forced the skeleton + retry UI onto the
  // home strip and category grid just to show a list the app already has.
  static List<Category> getCategories() => List.unmodifiable(_browsableRoots);

  /// Every shipped category, including the hidden `others` catch-all that
  /// [getCategories] omits. Use for lookups that must resolve legacy records.
  static List<Category> get all => List.unmodifiable(_shipped);

  /// Resolves a root id or a subcategory slug to the category that owns it.
  ///
  /// Subcategory ids are slugs while the owning category owns the products page,
  /// so a product stored under a child slug has to resolve up to its root.
  static Category? byId(String id) {
    for (final c in _shipped) {
      if (c.id == id) return c;
      if (c.subcategories.any((s) => s.id == id)) return c;
    }
    return null;
  }

  static List<Category>? _shippedCache;

  static List<Category> get _shipped =>
      _shippedCache ??= getDefaultCategories();

  static List<Category> get _browsableRoots => _shipped
      .where((c) => c.isActive)
      .toList(growable: false);

  // =========================
  // LIVE TREE (stream)
  // =========================
  /// Live categories from Firestore, or the HTTP v1 tree while the migration
  /// flag is set. Callers that only need to render a list should prefer the
  /// static [getCategories] and treat this as an optional refresh.
  Stream<List<Category>> watchCategories() {
    if (ApiConfig.kUseCategoriesApi) {
      // v1 is HTTP, not a stream: resolve once from Postgres and replay the
      // cached tree; ProductApiClient keeps its own copy so the category pages
      // and the home grid never hit Firestore during the migration window.
      //
      // Broadcast + value replay rather than `Stream.fromFuture`, because this is
      // handed to a StreamBuilder: a fresh future-backed stream per call meant
      // one categories HTTP request per rebuild.
      // The HTTP path has no source stream of its own — the fetch IS the source.
      return _broadcast(const Stream<List<Category>>.empty(), () async {
        final cats = await _api.fetchCategories();
        _cached = cats.where((c) => c.isActive).toList();
        return _cached!;
      });
    }
    if (_cachedStream != null) return _cachedStream!;
    _cachedStream = _broadcast(
      _db.collection("categories").snapshots().map((snapshot) {
        if (snapshot.docs.isEmpty) {
          return getDefaultCategories();
        }
        final cats = snapshot.docs
            .map((doc) => Category.fromFirestore(doc))
            .toList();
        cats.sort((a, b) => a.order.compareTo(b.order));
        _cached = cats.where((c) => c.isActive).toList();
        return _cached!;
      }),
      null,
    );
    return _cachedStream!;
  }

  List<Category>? _httpLast;

  /// Wraps a source stream in a broadcast controller that replays its last value
  /// to each new subscriber, so a remounted widget is not stuck on "loading"
  /// and a rebuild does not re-subscribe.
  Stream<List<Category>> _broadcast(
    Stream<List<Category>> source,
    Future<List<Category>> Function()? seed,
  ) {
    late final StreamController<List<Category>> ctrl;
    var started = false;

    ctrl = StreamController<List<Category>>.broadcast(
      onListen: () {
        if (started) {
          // Replay so a late subscriber renders immediately.
          final last = _httpLast;
          if (last != null) scheduleMicrotask(() => ctrl.add(last));
          return;
        }
        started = true;
        if (seed != null) {
          seed().then((v) {
            _httpLast = v;
            if (!ctrl.isClosed) ctrl.add(v);
          }).catchError((_) {});
        }
        source.listen((v) {
          _httpLast = v;
          if (!ctrl.isClosed) ctrl.add(v);
        }, onError: (Object _) {});
      },
    );
    return ctrl.stream;
  }

  List<Category> get cached => _cached ?? [];

  /// Drops the cached Firestore category stream so the next [watchCategories]
  /// call subscribes fresh. Used by the home screen retry UI after a
  /// stream timeout — a timed-out single-subscription stream cannot be reused.
  void invalidateCachedStream() {
    _cachedStream = null;
  }

  // =========================
  // GET CATEGORY BY ID
  // =========================
  Future<Category?> getCategoryById(String categoryId) async {
    if (ApiConfig.kUseCategoriesApi) {
      final cats = await _api.fetchCategories();
      for (final c in cats) {
        if (c.id == categoryId) return c;
        // Subcategory (child category) ids are slugs; the parent category owns
        // the products page, so resolve to the root.
        if (c.subcategories.any((s) => s.id == categoryId)) return c;
      }
      return null;
    }
    try {
      final doc = await _db.collection("categories").doc(categoryId).get();
      if (doc.exists) {
        return Category.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception("Failed to get category: $e");
    }
  }

  Future<void> addDefaultCategories() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      final token = await user.getIdToken(true);
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/categories/add-defaults'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      final result = jsonDecode(resp.body);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to add default categories');
      }
    } catch (e) {
      throw Exception("Failed to add default categories: $e");
    }
  }

  Future<void> updateCategory(
    String categoryId,
    Map<String, dynamic> data,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      final token = await user.getIdToken(true);
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/categories/update'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({ 'categoryId': categoryId, 'data': data }),
      );
      final result = jsonDecode(resp.body);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to update category');
      }
    } catch (e) {
      throw Exception("Failed to update category: $e");
    }
  }
}
