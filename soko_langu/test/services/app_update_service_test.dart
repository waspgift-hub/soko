import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/services/app_update_service.dart';

void main() {
  test('unpublished releases never count as newer', () {
    const info = AppReleaseInfo(
      published: false,
      latestVersion: '9.9.9',
      latestBuild: 99,
      minSupportedBuild: 99,
      urgency: 'required',
      releaseNotes: 'n/a',
      androidDownloadUrl: '',
      iosDownloadUrl: '',
    );
    expect(info.isNewerThan(1), isFalse);
    expect(info.isRequiredFor(1), isFalse);
  });

  test('published recommended updates compare build numbers', () {
    const info = AppReleaseInfo(
      published: true,
      latestVersion: '1.0.2',
      latestBuild: 3,
      minSupportedBuild: 1,
      urgency: 'recommended',
      releaseNotes: 'bug fixes',
      androidDownloadUrl: '',
      iosDownloadUrl: '',
    );
    expect(info.isNewerThan(2), isTrue);
    expect(info.isNewerThan(3), isFalse);
    expect(info.isRequiredFor(2), isFalse);
  });
}
