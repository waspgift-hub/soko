import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/banner_model.dart';

BannerCampaign _campaign({
  BannerStatus status = BannerStatus.active,
  DateTime? start,
  DateTime? end,
  BannerAudience audience = BannerAudience.allUsers,
  int? impressionLimit,
  int impressionCount = 0,
  int? clickLimit,
  int clickCount = 0,
  List<String>? deviceTargeting,
}) {
  final now = DateTime.now();
  return BannerCampaign(
    id: 'b1',
    title: 'Test',
    mainText: 'Body',
    type: BannerType.promotion,
    ctaLabel: 'Shop',
    destinationType: BannerDestinationType.flashSalePage,
    destinationValue: '',
    placement: BannerPlacement.homeFeed,
    priority: 1,
    startDate: start ?? now.subtract(const Duration(days: 1)),
    endDate: end ?? now.add(const Duration(days: 1)),
    targetAudience: audience,
    status: status,
    impressionLimit: impressionLimit,
    impressionCount: impressionCount,
    clickLimit: clickLimit,
    clickCount: clickCount,
    deviceTargeting: deviceTargeting,
  );
}

void main() {
  test('active campaign in schedule is currently active', () {
    expect(_campaign().isCurrentlyActive(), isTrue);
  });
  test('draft campaign is not active', () {
    expect(_campaign(status: BannerStatus.draft).isCurrentlyActive(), isFalse);
  });
  test('impression limit blocks eligibility', () {
    final c = _campaign(impressionLimit: 10, impressionCount: 10);
    expect(c.hasReachedImpressionLimit(), isTrue);
    expect(
      c.isEligibleForUser(
        isSignedIn: true,
        isSeller: false,
        isBusinessAccount: false,
        isKycApproved: false,
        isBlueTick: false,
      ),
      isFalse,
    );
  });
  test('signed-in audience requires signed-in user', () {
    final c = _campaign(audience: BannerAudience.signedInUsers);
    expect(
      c.isEligibleForUser(
        isSignedIn: false,
        isSeller: false,
        isBusinessAccount: false,
        isKycApproved: false,
        isBlueTick: false,
      ),
      isFalse,
    );
    expect(
      c.isEligibleForUser(
        isSignedIn: true,
        isSeller: false,
        isBusinessAccount: false,
        isKycApproved: false,
        isBlueTick: false,
      ),
      isTrue,
    );
  });
  test('device targeting filters device type', () {
    final c = _campaign(deviceTargeting: ['mobile']);
    expect(
      c.isEligibleForUser(
        isSignedIn: true,
        isSeller: false,
        isBusinessAccount: false,
        isKycApproved: false,
        isBlueTick: false,
        deviceType: 'mobile',
      ),
      isTrue,
    );
    expect(
      c.isEligibleForUser(
        isSignedIn: true,
        isSeller: false,
        isBusinessAccount: false,
        isKycApproved: false,
        isBlueTick: false,
        deviceType: 'desktop',
      ),
      isFalse,
    );
  });
}
