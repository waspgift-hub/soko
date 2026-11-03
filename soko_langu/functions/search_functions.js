const functions = require('firebase-functions');
const query = require('./search/query');

// ─── SEARCH ───
exports.globalSearch = functions.https.onCall(query.globalSearch);
exports.searchAutocomplete = functions.https.onCall(query.searchAutocomplete);
exports.getTrendingSearches = functions.https.onCall(query.getTrendingSearches);
exports.recordSearchClick = functions.https.onCall(query.recordSearchClick);
