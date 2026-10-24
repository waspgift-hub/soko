import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/banner_model.dart';
import '../services/seller_verification_service.dart';

/// Service for managing and fetching banner campaigns.
///
/// This is the authoritative source for banner data in the app.
/// It handles:
/// - Fetching eligible banners for a placement
/// - Audience targeting and eligibility
/// - Impression and click tracking
/// - Caching and real-time updates
class BannerService {
  BannerService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SellerVerificationService? verificationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _verification = verificationService ?? SellerVerificationService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final SellerVerificationService _verification;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bannerSubscription;
  final Map<BannerPlacement, List<BannerCampaign>> _cachedBanners = {};
  final StreamController<Map<BannerPlacement, List<BannerCampaign>>> _bannerController =
      StreamController.broadcast();

  /// Stream of eligible banners for all placements.
  Stream<Map<BannerPlacement, List<BannerCampaign>>> get bannersStream =>
      _bannerController.stream;

  /// Current cached banners for a placement.
  List<BannerCampaign> getBannersForPlacement(BannerPlacement placement) {
    return _cachedBanners[placement] ?? [];
  }

  /// Starts listening to banner changes from Firestore.
  Future<void> start() async {
    await _verification.refresh();
    _subscribeToBanners();
  }

  /// Stops listening to banner changes.
  void dispose() {
    _bannerSubscription?.cancel();
    _bannerController.close();
  }

  void _subscribeToBanners() {
    _bannerSubscription = _firestore
        .collection('banner_campaigns')
        .where('status', isEqualTo: 'active')
        .orderBy('priority', descending: true)
        .snapshots()
        .listen(_onBannersChanged, onError: (error) {
      debugPrint('BannerService: stream error — $error');
    });
  }

  void _onBannersChanged(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final now = DateTime.now();
    final user = _auth.currentUser;

    // Get user context for eligibility
    final isSignedIn = user != null;
    final isSeller = false; // Would need to check user role
    final isBusinessAccount = false; // Would need to check user role
    final isKycApproved = _verification.isSelfBlueTick;
    final isBlueTick = _verification.isSelfBlueTick;

    // Determine device type (simplified)
    String? deviceType;
    // In a real app, you'd use device_info_plus or similar

    final Map<BannerPlacement, List<BannerCampaign>> bannersByPlacement = {};

    for (final doc in snapshot.docs) {
      final campaign = BannerCampaign.fromFirestore(doc);

      // Check schedule
      if (!campaign.isCurrentlyActive(now: now)) continue;

      // Check audience eligibility
      if (!campaign.isEligibleForUser(
        isSignedIn: isSignedIn,
        isSeller: isSeller,
        isBusinessAccount: isBusinessAccount,
        isKycApproved: isKycApproved,
        isBlueTick: isBlueTick,
        deviceType: deviceType,
      )) continue;

      // Add to placement list
      final placement = campaign.placement;
      bannersByPlacement.putIfAbsent(placement, () => []).add(campaign);
    }

    // Sort each placement by priority (highest first)
    for (final placement in bannersByPlacement.keys) {
      bannersByPlacement[placement]!
          .sort((a, b) => b.priority.compareTo(a.priority));
    }

    // Update cache
    _cachedBanners.clear();
    _cachedBanners.addAll(bannersByPlacement);

    // Emit to stream
    _bannerController.add(Map.unmodifiable(bannersByPlacement));
  }

  /// Records an impression for a banner.
  Future<void> recordImpression({
    required String bannerId,
    required BannerPlacement placement,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Update impression count in campaign
      await _firestore.collection('banner_campaigns').doc(bannerId).update({
        'impressionCount': FieldValue.increment(1),
      });

      // Log impression event
      await _firestore.collection('banner_impressions').add(
        BannerImpressionEvent(
          bannerId: bannerId,
          userId: user.uid,
          placement: placement,
          timestamp: DateTime.now(),
        ).toFirestore(),
      );
    } catch (e) {
      debugPrint('BannerService: failed to record impression — $e');
    }
  }

  /// Records a click for a banner.
  Future<void> recordClick({
    required String bannerId,
    required BannerPlacement placement,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Update click count in campaign
      await _firestore.collection('banner_campaigns').doc(bannerId).update({
        'clickCount': FieldValue.increment(1),
      });

      // Log click event
      await _firestore.collection('banner_clicks').add(
        BannerClickEvent(
          bannerId: bannerId,
          userId: user.uid,
          placement: placement,
          timestamp: DateTime.now(),
        ).toFirestore(),
      );
    } catch (e) {
      debugPrint('BannerService: failed to record click — $e');
    }
  }

  /// Fetches a single banner by ID (for admin preview).
  Future<BannerCampaign?> getBannerById(String bannerId) async {
    try {
      final doc = await _firestore
          .collection('banner_campaigns')
          .doc(bannerId)
          .get();
      if (!doc.exists) return null;
      return BannerCampaign.fromFirestore(doc);
    } catch (e) {
      debugPrint('BannerService: failed to get banner — $e');
      return null;
    }
  }
}