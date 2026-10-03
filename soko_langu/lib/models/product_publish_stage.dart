/// Phase of a product publish, reported so the seller sees honest progress
/// instead of an indeterminate spinner during what should be a ~2 second action.
///
/// Lives in its own file so the publishing UI and its tests do not have to
/// import the whole `ProductService` graph (which reaches the catalogue API).
enum ProductPublishStage {
  /// Reading the seller record and checking the unverified product limit.
  checking,

  /// Compressing and uploading the photos. Runs concurrently, not one by one.
  uploadingImages,

  /// Writing the listing.
  saving,

  /// Uploading a freshly picked clip. Reported *after* the listing is already
  /// live, because a video cannot finish inside the publish budget.
  uploadingVideo,

  done,
}