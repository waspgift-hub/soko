import '../../models/seller_verification.dart';

/// The only trust signal [AdManager] is permitted to consult.
///
/// Exists as an interface so the ad decision layer can be unit-tested without a
/// Firebase instance. Production wires in `SellerVerificationService`, which
/// reads server-written state; tests wire a fixed snapshot. There is deliberately
/// no member here that accepts a client-supplied `isVerified`, `isBlueTick` or
/// `adsExempt` flag — such a value has no path into the ad system at all.
abstract class AdEligibilitySource {
  /// True when the signed-in account is excluded from all normal AdMob
  /// inventory. Derived from trusted state, never asserted by a caller.
  bool get isSelfAdExempt;

  /// True when the signed-in account has an ACTIVE Blue Tick.
  bool get isSelfBlueTick;

  SellerVerification get selfVerification;

  /// Cached verification for badge rendering. False while unknown, so a badge
  /// never appears before trusted state resolves — and disappears the moment a
  /// revocation lands.
  bool isBlueTick(String sellerId);

  /// Re-reads trusted state. Called on launch and on every auth transition.
  Future<void> refresh();

  /// AdManager subscribes so a grant or revocation re-evaluates every mounted
  /// slot without a restart.
  void addListener(void Function() listener);

  void removeListener(void Function() listener);
}

/// A fixed eligibility snapshot for tests and previews.
class StaticAdEligibility implements AdEligibilitySource {
  StaticAdEligibility([SellerVerification? self])
      : _self = self ?? SellerVerification.unknown;

  SellerVerification _self;
  final Map<String, SellerVerification> _others = {};
  final List<void Function()> _listeners = [];

  /// Simulates a grant or revocation arriving from the trusted backend.
  void updateSelf(SellerVerification next) {
    _self = next;
    for (final l in List<void Function()>.from(_listeners)) {
      l();
    }
  }

  /// Registers a seller other than the signed-in account.
  void setOther(SellerVerification v) => _others[v.sellerId] = v;

  @override
  bool get isSelfAdExempt => _self.isAdExempt;

  @override
  bool get isSelfBlueTick => _self.isBlueTickActive;

  @override
  SellerVerification get selfVerification => _self;

  @override
  bool isBlueTick(String sellerId) =>
      (_others[sellerId] ?? (sellerId == _self.sellerId ? _self : null))
          ?.isBlueTickActive ??
      false;

  @override
  Future<void> refresh() async {}

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);
}