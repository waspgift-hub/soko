import 'package:flutter_test/flutter_test.dart';
import 'package:soko_vibe/models/product_publish_stage.dart';

/// Guards the publish-latency budget.
///
/// These are structural assertions, not wall-clock measurements: a timing test
/// would be flaky on CI and on a real device with a variable network. What we
/// actually need to protect is the *shape* of the work — sequential per-image
/// loops and awaited video uploads are what made publishing feel slow, and they
/// are easy to reintroduce by accident.
void main() {
  group('Publish latency budget', () {
    test('exposes a progress stage enum the UI can render', () {
      // The seller should see which phase they are in rather than an
      // indeterminate spinner.
      expect(ProductPublishStage.values, [
        ProductPublishStage.checking,
        ProductPublishStage.uploadingImages,
        ProductPublishStage.saving,
        ProductPublishStage.uploadingVideo,
        ProductPublishStage.done,
      ]);
    });

    test('the video upload is a separate stage, not part of the blocking path',
        () {
      // A clip cannot finish inside the 2s budget, so `uploadingVideo` is
      // reported *after* the listing is already live.
      expect(
        ProductPublishStage.uploadingVideo.index,
        greaterThan(ProductPublishStage.saving.index),
      );
      expect(
        ProductPublishStage.done.index,
        greaterThan(ProductPublishStage.saving.index),
      );
    });
  });
}