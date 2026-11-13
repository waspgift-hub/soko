import 'package:flutter/foundation.dart';

/// KYC review status. Mirrors the server vocabulary exactly
/// (`server/src/modules/kyc/kyc-service.js`) — the client never invents a
/// status, it only renders what the trusted backend reported.
enum KycStatus {
  none,
  pending,
  approved,
  rejected,
  revoked;

  static KycStatus parse(Object? raw) {
    switch ((raw?.toString() ?? '').trim().toLowerCase()) {
      case 'approved':
        return KycStatus.approved;
      case 'pending':
        return KycStatus.pending;
      case 'rejected':
        return KycStatus.rejected;
      case 'revoked':
        return KycStatus.revoked;
      default:
        return KycStatus.none;
    }
  }
}

/// Admin-controlled Blue Tick state.
///
/// [active] is never set by a client write. The server derives it in
/// `server/src/modules/ads/blue-tick.js` from `kyc.approved == true &&
/// verificationStatus == 'verified' && revokedAt == null`, and the Firestore
/// `users/{uid}.trust` subdocument it writes is append-guarded in
/// `firestore.rules`, so a seller cannot grant themselves a tick.
enum BlueTickStatus {
  none,
  pending,
  active,
  revoked;

  static BlueTickStatus parse(Object? raw) {
    switch ((raw?.toString() ?? '').trim().toLowerCase()) {
      case 'active':
      case 'granted':
      case 'verified':
        return BlueTickStatus.active;
      case 'pending':
      case 'requested':
        return BlueTickStatus.pending;
      case 'revoked':
      case 'suspended':
        return BlueTickStatus.revoked;
      default:
        return BlueTickStatus.none;
    }
  }
}

/// Authoritative verification snapshot for one seller.
///
/// Constructed only from trusted sources: the authenticated `/users/me`
/// response, the server trust passport, or a server-written Firestore
/// `users/{uid}.trust` doc. Any field the client could have self-assigned
/// (`isVerified`, `isBlueTick`, `adsExempt`) is deliberately absent from this
/// type so no call site can consult one.
@immutable
class SellerVerification {
  const SellerVerification({
    required this.sellerId,
    this.kycStatus = KycStatus.none,
    this.kycApproved = false,
    this.blueTick = BlueTickStatus.none,
    this.storeName = '',
    this.grantedAt,
    this.revokedAt,
  });

  final String sellerId;
  final KycStatus kycStatus;
  final bool kycApproved;
  final BlueTickStatus blueTick;
  final String storeName;
  final DateTime? grantedAt;
  final DateTime? revokedAt;

  static const SellerVerification unknown =
      SellerVerification(sellerId: '');

  /// The single definition of a granted Blue Tick. KYC approval alone is not
  /// enough — the tick also has to be ACTIVE and not revoked — and KYC is
  /// revoked/pending/rejected states always resolve to no tick.
  bool get isBlueTickActive =>
      kycApproved &&
      kycStatus == KycStatus.approved &&
      blueTick == BlueTickStatus.active;

  /// True while the seller has submitted KYC and is waiting on review. They see
  /// normal advertising.
  bool get isKycPending => kycStatus == KycStatus.pending;

  bool get isKycRejected =>
      kycStatus == KycStatus.rejected || kycStatus == KycStatus.revoked;

  /// Server-computed ad exemption. Blue Tick sellers are excluded from all
  /// normal AdMob inventory; nobody else is.
  bool get isAdExempt => isBlueTickActive;

  /// Parses the trust passport envelope from `GET /api/v1/trust/sellers/:id/passport`.
  static SellerVerification fromPassport(
    String sellerId,
    Map<String, dynamic> data,
  ) {
    final seller = (data['seller'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trust = (data['trust'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kyc = (seller['kyc'] as Map?)?.cast<String, dynamic>() ??
        (trust['kyc'] as Map?)?.cast<String, dynamic>() ??
        const {};

    DateTime? parseTs(Object? v) {
      if (v is! String || v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    return SellerVerification(
      sellerId: sellerId,
      kycStatus: KycStatus.parse(kyc['status'] ?? seller['kycStatus']),
      kycApproved: kyc['approved'] == true ||
          seller['kycApproved'] == true ||
          trust['kycApproved'] == true,
      blueTick: BlueTickStatus.parse(
        trust['blueTick'] ?? seller['blueTick'] ?? data['blueTick'],
      ),
      storeName: (seller['storeName'] as String?) ?? '',
      grantedAt: parseTs(trust['blueTickGrantedAt'] ?? data['blueTickGrantedAt']),
      revokedAt: parseTs(trust['blueTickRevokedAt'] ?? data['blueTickRevokedAt']),
    );
  }

  /// Parses the authenticated self-profile envelope (`GET /api/v1/users/me`).
  static SellerVerification fromSelfProfile(
    String uid,
    Map<String, dynamic> data,
  ) {
    final kyc = (data['kyc'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trust = (data['trust'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SellerVerification(
      sellerId: uid,
      kycStatus: KycStatus.parse(kyc['status']),
      kycApproved: kyc['approved'] == true,
      blueTick: BlueTickStatus.parse(trust['blueTick']),
      storeName: (data['displayName'] as String?) ?? '',
      grantedAt: DateTime.tryParse(trust['blueTickGrantedAt'] as String? ?? ''),
      revokedAt: DateTime.tryParse(trust['blueTickRevokedAt'] as String? ?? ''),
    );
  }

  /// Parses a server-written Firestore `users/{uid}` document.
  ///
  /// `kyc` and `trust` are both in `noSensitiveFieldChanges` /
  /// `noSensitiveCreateFields` in `firestore.rules`, so a client cannot author
  /// either map. Reads are the only thing that is allowed.
  ///
  /// Timestamps arrive already converted to ISO strings by the Firestore reader,
  /// which keeps this model free of a `cloud_firestore` dependency.
  static SellerVerification fromFirestoreDoc(
    String uid,
    Map<String, dynamic> data,
  ) {
    final kyc = (data['kyc'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trust = (data['trust'] as Map?)?.cast<String, dynamic>() ?? const {};

    DateTime? readTs(Object? v) {
      if (v is! String || v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    return SellerVerification(
      sellerId: uid,
      kycStatus: KycStatus.parse(kyc['status']),
      kycApproved: kyc['approved'] == true,
      blueTick: BlueTickStatus.parse(trust['blueTick']),
      storeName: (data['displayName'] as String?) ?? '',
      grantedAt: readTs(trust['blueTickGrantedAt']),
      revokedAt: readTs(trust['blueTickRevokedAt']),
    );
  }

  SellerVerification copyWith({
    KycStatus? kycStatus,
    bool? kycApproved,
    BlueTickStatus? blueTick,
  }) =>
      SellerVerification(
        sellerId: sellerId,
        kycStatus: kycStatus ?? this.kycStatus,
        kycApproved: kycApproved ?? this.kycApproved,
        blueTick: blueTick ?? this.blueTick,
        storeName: storeName,
        grantedAt: grantedAt,
        revokedAt: revokedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is SellerVerification &&
      other.sellerId == sellerId &&
      other.kycStatus == kycStatus &&
      other.kycApproved == kycApproved &&
      other.blueTick == blueTick;

  @override
  int get hashCode => Object.hash(sellerId, kycStatus, kycApproved, blueTick);

  @override
  String toString() =>
      'SellerVerification($sellerId, kyc=$kycStatus/$kycApproved, '
      'tick=$blueTick, exempt=$isAdExempt)';
}
