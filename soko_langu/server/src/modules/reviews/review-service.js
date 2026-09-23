// Firestore-only review operations (Phase 3). Thin passthrough to
// review-store so the Express routes keep importing the service identity.
const store = require('./review-store');

async function listProductReviews(args) {
  return store.listProductReviews(args);
}

async function getMyReview(args) {
  return store.getMyReview(args);
}

async function upsertReview(args) {
  return store.upsertReview(args);
}

async function toggleHelpful(args) {
  return store.toggleHelpful(args);
}

async function replyToReview(args) {
  return store.replyToReview(args);
}

async function sellerRatingSummary(args) {
  return store.sellerRatingSummary(args);
}

module.exports = {
  listProductReviews,
  getMyReview,
  upsertReview,
  toggleHelpful,
  replyToReview,
  sellerRatingSummary,
};