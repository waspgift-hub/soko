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
        .map((snap) {
      // BuyerRequest.fromFirestore tolerates legacy shapes (string budgets,
      // missing timestamps), so the stream never dies on one bad document.
      return snap.docs
          .map((doc) => BuyerRequest.fromFirestore(doc))
          .toList();
    });
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
      'whatsapp': _toWaMeLink(whatsapp),
      'isLocked': true,
      'unlockedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Normalizes a local phone number like 0712345678 into a wa.me link.
  String _toWaMeLink(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = '255${digits.substring(1)}';
    } else if (!digits.startsWith('255')) {
      digits = '255$digits';
    }
    return 'https://wa.me/$digits';
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
