import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/seller_verification.dart';
import 'ads/ad_eligibility_source.dart';
import 'api_config.dart';
import 'trust_api.dart';

/// Resolves authoritative seller verification (KYC + Blue Tick) for the current
/// user and for any seller whose identity is rendered.
///
/// Trust boundary
/// --------------
/// Everything here is a *read* of server-written state. The client never posts
/// a verification status, never sends an `isVerified`/`isBlueTick`/`adsExempt`
/// flag, and never derives the Blue Tick locally from something a user typed.
/// Concretely:
///
/// * Self state comes from `GET /api/v1/users/me` (authenticated) with a
///   Firestore `users/{uid}` snapshot as the degraded path.
/// * Other sellers come from the public trust passport
///   `GET /api/v1/trust/sellers/:id/passport`, whose `trust.blueTick` field is
///   computed server-side.
/// * `firestore.rules` lists `kyc`, `trust` and `sellerKycApproved` in
///   `noSensitiveFieldChanges` / `noSensitiveCreateFields`, so a direct
///   Firestore SDK write of any of them is rejected.
///
/// Because nothing is cached across accounts, logging out and signing in as a
/// different user cannot inherit the previous user's exemption: [clear] runs on
/// every auth transition.
class SellerVerificationService extends ChangeNotifier implements AdEligibilitySource {
  SellerVerificationService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    TrustApiClient? trustApi,
    http.Client? httpClient,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _trustApi = trustApi ?? TrustApiClient(),
        _http = httpClient ?? http.Client() {
    _uidSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final TrustApiClient _trustApi;
  final http.Client _http;

  StreamSubscription<User?>? _uidSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _selfSub;

  final Map<String, SellerVerification> _cache = {};
  final Map<String, Future<SellerVerification?>> _inFlight = {};

  SellerVerification _self = SellerVerification.unknown;
  String? _selfUid;
  bool _selfResolving = false;

/// Verification state of the signed-in user. Unknown until resolved, which
  /// means "not exempt" — ads stay on until trusted state proves otherwise.
  @override
  SellerVerification get selfVerification => _self;

  String? get selfUid => _selfUid;

  bool get isSelfResolving => _selfResolving;

  /// The only signal the ad system is allowed to consult.
  @override
  bool get isSelfAdExempt => _self.isAdExempt;

  @override
  bool get isSelfBlueTick => _self.isBlueTickActive;

  @override
  Future<void> refresh() => refreshSelf();

  SellerVerification? verificationOf(String sellerId) => _cache[sellerId];

  /// Cached Blue Tick state for badge rendering. Returns false while unknown so
  /// a badge never flashes on before the trusted read resolves.
  @override
  bool isBlueTick(String sellerId) =>
      _cache[sellerId]?.isBlueTickActive ?? false;

  Future<void> _onAuthChanged(User? user) async {
    await _teardownSelfListener();
    _cache.clear();
    _inFlight.clear();
    _selfUid = user?.uid;
    _self = SellerVerification.unknown;
    notifyListeners();
    if (user == null) return;
    await refreshSelf();
  }

  Future<void> _teardownSelfListener() async {
    await _selfSub?.cancel();
    _selfSub = null;
  }

  /// Re-reads the signed-in user's trusted verification state.
  ///
  /// Called at launch, on every auth transition, and whenever the server-side
  /// trust document changes. [resetSelfResolver] exists for tests.
  Future<SellerVerification> refreshSelf({bool listen = true}) async {
    final uid = _selfUid ?? _auth.currentUser?.uid;
    if (uid == null) {
      _self = SellerVerification.unknown;
      _selfUid = null;
      return _self;
    }
    _selfUid = uid;
    _selfResolving = true;
    notifyListeners();

    final resolved = await _resolveSelf(uid);
    // Guard against a slow response for a previous uid landing after a logout.
    if (_selfUid != uid) return _self;

    _self = resolved;
    _selfResolving = false;
    _cache[uid] = resolved;
    notifyListeners();

    if (listen) {
      await _teardownSelfListener();
      _selfSub = _db
          .collection('users')
          .doc(uid)
          .snapshots(includeMetadataChanges: false)
          .listen(
        (snap) {
          if (_selfUid != uid || !snap.exists) return;
          final next = SellerVerification.fromFirestoreDoc(
            uid,
            _normalizeFirestoreDoc(snap.data() ?? const {}),
          );
          if (next == _self) return;
          _self = next;
          _cache[uid] = next;
          notifyListeners();
        },
        onError: (_) {/* offline or denied: keep the last trusted value */},
      );
    }
    return _self;
  }

  Future<SellerVerification> _resolveSelf(String uid) async {
    final api = await _resolveSelfFromApi(uid);
    if (api != null) return api;
    return _resolveSelfFromFirestore(uid);
  }

  Future<SellerVerification?> _resolveSelfFromApi(String uid) async {
    try {
      final token = await _auth.currentUser?.getIdToken();
      if (token == null) return null;
final res = await _http
          .get(Uri.parse(ApiConfig.v1('/users/me')), headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final data = body is Map && body['data'] is Map
          ? (body['data'] as Map).cast<String, dynamic>()
          : (body is Map ? body.cast<String, dynamic>() : null);
      if (data == null) return null;
      return SellerVerification.fromSelfProfile(uid, data);
    } catch (_) {
      return null;
    }
  }

  Future<SellerVerification> _resolveSelfFromFirestore(String uid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!snap.exists) return SellerVerification(sellerId: uid);
      return SellerVerification.fromFirestoreDoc(
        uid,
        _normalizeFirestoreDoc(snap.data() ?? const {}),
      );
    } catch (_) {
      return SellerVerification(sellerId: uid);
    }
  }

  /// Resolves (and caches) a seller's verification state for badge rendering.
  ///
  /// Concurrent callers for the same seller share one request.
  Future<SellerVerification?> resolve(String sellerId) {
    if (sellerId.isEmpty) return Future.value(null);
    final cached = _cache[sellerId];
    if (cached != null) return Future.value(cached);
    final pending = _inFlight[sellerId];
    if (pending != null) return pending;

    final future = _resolveRemote(sellerId).then((value) {
      _inFlight.remove(sellerId);
      if (value != null) {
        _cache[sellerId] = value;
        notifyListeners();
      }
      return value;
    });
    _inFlight[sellerId] = future;
    return future;
  }

/// Resolves ANOTHER seller's badge state.
  ///
  /// Order matters: the trust API is authoritative, and the Firestore fallback
  /// reads `userPublic/{sellerId}` — the public projection — because the private
  /// `users/{sellerId}` doc is owner-scoped by firestore.rules and would now be
  /// denied. The projection carries exactly the coarse `kycApproved` flag a
  /// badge needs, so nothing is lost.
  Future<SellerVerification?> _resolveRemote(String sellerId) async {
    if (!ApiConfig.kUseTrustApi) return null;
    final passport = await _trustApi.fetchPassport(sellerId);
    if (passport != null) return SellerVerification.fromPassport(sellerId, passport);
    try {
      final snap = await _db
          .collection('userPublic')
          .doc(sellerId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!snap.exists) return null;
      return SellerVerification.fromFirestoreDoc(
        sellerId,
        _normalizeFirestoreDoc(snap.data() ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }

  /// Seeds verification for a search result / product card so a badge can render
  /// without waiting on a network round-trip. Only ever fed from a trusted API
  /// payload; there is no client-authored write path.
  void seedFromTrustedPayload(String sellerId, SellerVerification value) {
    if (sellerId.isEmpty || sellerId == _selfUid) return;
    _cache[sellerId] = value;
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
    _self = SellerVerification.unknown;
    _selfResolving = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_uidSub?.cancel());
    unawaited(_teardownSelfListener());
    _http.close();
    super.dispose();
  }

  /// Converts Firestore `Timestamp` values to ISO strings so the model stays
  /// transport-agnostic and unit-testable without a Firestore instance.
  static Map<String, dynamic> _normalizeFirestoreDoc(Map<String, dynamic> src) {
    final kycRaw = src['kyc'];
    final trustRaw = src['trust'];
    return {
      'displayName': src['displayName'],
      'kyc': kycRaw is Map ? _isoify(kycRaw.cast<String, dynamic>()) : const {},
      'trust':
          trustRaw is Map ? _isoify(trustRaw.cast<String, dynamic>()) : const {},
    };
  }

  static Map<String, dynamic> _isoify(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((key, value) {
      if (value is Timestamp) {
        out[key] = value.toDate().toIso8601String();
      } else if (value is Map) {
        out[key] = _isoify(value.cast<String, dynamic>());
      } else {
        out[key] = value;
      }
    });
    return out;
  }
}

/// Process-wide instance, registered in main.dart's MultiProvider.
///
/// One instance matters: it holds the per-seller verification cache and the
/// live Firestore subscription for the signed-in user, so a grant or a
/// revocation reaches every badge and the ad system at the same moment.
final SellerVerificationService sellerVerificationService =
    SellerVerificationService();
