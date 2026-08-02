import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/buyer_request_model.dart';

class BuyerRequestService {
  static const String collection = 'BuyerRequests';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<BuyerRequest>> getRequests() {
    return _db
        .collection(collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => BuyerRequest.fromFirestore(doc)).toList());
  }

  /// Posts a new request with the contact locked until a seller unlocks it.
  Future<void> addRequest({
    required String title,
    required double budget,
    required String description,
    required String whatsapp,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    await _db.collection(collection).add({
      'buyerUid': user.uid,
      'buyerName': user.displayName ?? '',
      'title': title,
      'budget': budget,
      'description': description,
      'whatsapp': whatsapp,
      'isLocked': true,
      'unlockedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently unlocks the buyer's contact for the signed-in seller.
  Future<void> unlockContact(String requestId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    await _db.collection(collection).doc(requestId).update({
      'unlockedBy': FieldValue.arrayUnion([user.uid]),
    });
  }
}
