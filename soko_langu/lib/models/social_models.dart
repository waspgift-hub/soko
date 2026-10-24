import 'package:cloud_firestore/cloud_firestore.dart';

/// A one-directional "follow" relationship: [followerId] follows [followingId].
///
/// Stored in Firestore as `users/{followerId}/following/{followingId}` (and the
/// mirrored `users/{followingId}/followers/{followerId}`).
///
/// Both edges are written in a single batch by [FollowService] so the graph is
/// always consistent: the doc exists on both sides iff the follow is active.
@immutable
class FollowRelationship {
  const FollowRelationship({
    required this.followerId,
    required this.followingId,
    required this.createdAt,
  });

  final String followerId;
  final String followingId;
  final DateTime createdAt;

  factory FollowRelationship.fromDoc(String followerId, String followingId, Map<String, dynamic> d) {
    return FollowRelationship(
      followerId: followerId,
      followingId: followingId,
      createdAt: _ts(d['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'followerId': followerId,
    'followingId': followingId,
    'createdAt': FieldValue.serverTimestamp(),
  };

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowRelationship &&
          runtimeType == other.runtimeType &&
          followerId == other.followerId &&
          followingId == other.followingId;

  @override
  int get hashCode => Object.hash(followerId, followingId);
}

/// A pending follow request sent by [requesterId] to [targetId] when [targetId]
/// has a private account. Stored as
/// `users/{targetId}/followRequests/{requesterId}`.
///
/// The relationship only becomes active when the target approves the request,
/// at which point [FollowService.acceptRequest] writes the full [FollowRelationship]
/// edges and deletes this request doc.
@immutable
class FollowRequest {
  const FollowRequest({
    required this.requesterId,
    required this.targetId,
    required this.createdAt,
  });

  final String requesterId;
  final String targetId;
  final DateTime createdAt;

  factory FollowRequest.fromDoc(String requesterId, String targetId, Map<String, dynamic> d) {
    return FollowRequest(
      requesterId: requesterId,
      targetId: targetId,
      createdAt: _ts(d['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'requesterId': requesterId,
    'targetId': targetId,
    'createdAt': FieldValue.serverTimestamp(),
  };

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowRequest &&
          runtimeType == other.runtimeType &&
          requesterId == other.requesterId &&
          targetId == other.targetId;

  @override
  int get hashCode => Object.hash(requesterId, targetId);
}

/// A block: [blockerId] has blocked [blockedId].
///
/// Stored as `users/{blockerId}/blocked/{blockedId}`.
///
/// A blocked relationship:
/// - prevents the blocked user from following the blocker,
/// - prevents the blocked user from seeing the blocker's private-account content,
/// - removes any existing follow in both directions.
@immutable
class BlockedAccount {
  const BlockedAccount({
    required this.blockerId,
    required this.blockedId,
    required this.createdAt,
  });

  final String blockerId;
  final String blockedId;
  final DateTime createdAt;

  factory BlockedAccount.fromDoc(String blockerId, String blockedId, Map<String, dynamic> d) {
    return BlockedAccount(
      blockerId: blockerId,
      blockedId: blockedId,
      createdAt: _ts(d['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'blockerId': blockerId,
    'blockedId': blockedId,
    'createdAt': FieldValue.serverTimestamp(),
  };

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockedAccount &&
          runtimeType == other.runtimeType &&
          blockerId == other.blockerId &&
          blockedId == other.blockedId;

  @override
  int get hashCode => Object.hash(blockerId, blockedId);
}

/// Privacy settings for a profile. Stored on `users/{uid}` as
/// `visibility` (a sub-map) and also mirrored to `userPublic/{uid}`
/// so clients can render the public/private state without reading the
/// private doc.
@immutable
class ProfileVisibilitySettings {
  const ProfileVisibilitySettings({
    this.isPrivate = false,
    this.showFollowers = true,
    this.showFollowing = true,
    this.showProducts = true,
    this.allowContactDiscovery = true,
  });

  /// When true, only approved followers may see follower-restricted content.
  /// Public accounts show limited profile info to everyone.
  final bool isPrivate;

  /// Whether follower count/list is visible to non-followers.
  final bool showFollowers;

  /// Whether following count/list is visible to non-followers.
  final bool showFollowing;

  /// Whether the public products/listings grid is visible to non-followers.
  final bool showProducts;

  /// Whether this account may be surfaced by contact-based discovery.
  final bool allowContactDiscovery;

  factory ProfileVisibilitySettings.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const ProfileVisibilitySettings();
    return ProfileVisibilitySettings(
      isPrivate: d['isPrivate'] == true,
      showFollowers: d['showFollowers'] ?? true,
      showFollowing: d['showFollowing'] ?? true,
      showProducts: d['showProducts'] ?? true,
      allowContactDiscovery: d['allowContactDiscovery'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'isPrivate': isPrivate,
    'showFollowers': showFollowers,
    'showFollowing': showFollowing,
    'showProducts': showProducts,
    'allowContactDiscovery': allowContactDiscovery,
  };

  ProfileVisibilitySettings copyWith({
    bool? isPrivate,
    bool? showFollowers,
    bool? showFollowing,
    bool? showProducts,
    bool? allowContactDiscovery,
  }) =>
      ProfileVisibilitySettings(
        isPrivate: isPrivate ?? this.isPrivate,
        showFollowers: showFollowers ?? this.showFollowers,
        showFollowing: showFollowing ?? this.showFollowing,
        showProducts: showProducts ?? this.showProducts,
        allowContactDiscovery: allowContactDiscovery ?? this.allowContactDiscovery,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileVisibilitySettings &&
          runtimeType == other.runtimeType &&
          isPrivate == other.isPrivate &&
          showFollowers == other.showFollowers &&
          showFollowing == other.showFollowing &&
          showProducts == other.showProducts &&
          allowContactDiscovery == other.allowContactDiscovery;

  @override
  int get hashCode =>
      Object.hash(isPrivate, showFollowers, showFollowing, showProducts, allowContactDiscovery);
}

/// Verification trust signal for one user. Mirrors the trusted KYC/Blue Tick
/// derivation so the social UI never has to re-derive it.
///
/// The client never sets this; it is derived server-side (KYC approved +
/// admin-granted Blue Tick) and exposed via the `userPublic` projection so
/// badge rendering never touches the private `users/{uid}` doc.
@immutable
class UserTrustState {
  const UserTrustState({
    required this.sellerId,
    this.kycStatus = KycReviewStatus.none,
    this.kycApproved = false,
    this.blueTick = BlueTickStatus.none,
  });

  final String sellerId;
  final KycReviewStatus kycStatus;
  final bool kycApproved;
  final BlueTickStatus blueTick;

  bool get isBlueTickActive =>
      kycApproved && kycStatus == KycReviewStatus.approved && blueTick == BlueTickStatus.active;

  factory UserTrustState.fromMap(String sellerId, Map<String, dynamic>? d) {
    if (d == null) return UserTrustState(sellerId: sellerId);
    return UserTrustState(
      sellerId: sellerId,
      kycStatus: KycReviewStatus.values.firstWhere(
        (e) => e.name == (d['kycStatus'] as String? ?? 'none'),
        orElse: () => KycReviewStatus.none,
      ),
      kycApproved: d['kycApproved'] == true,
      blueTick: BlueTickStatus.values.firstWhere(
        (e) => e.name == (d['blueTick'] as String? ?? 'none'),
        orElse: () => BlueTickStatus.none,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'kycStatus': kycStatus.name,
    'kycApproved': kycApproved,
    'blueTick': blueTick.name,
  };
}

/// KYC review status vocabulary — mirrors the server KYC service exactly.
enum KycReviewStatus { none, pending, approved, rejected, revoked }

/// Admin-controlled Blue Tick state. Mirrors the server derivation exactly.
enum BlueTickStatus { none, pending, active, revoked }