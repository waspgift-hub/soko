import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DisputeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> createDispute({
    required String orderId,
    required String reason,
    required String description,
    List<String>? imageUrls,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    await _db.collection('disputes').add({
      'orderId': orderId,
      'buyerId': user.uid,
      'reason': reason,
      'description': description,
      'imageUrls': imageUrls ?? [],
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'resolution': '',
      'resolvedBy': '',
      'resolvedAt': null,
    });
  }

  Stream<List<Map<String, dynamic>>> getMyDisputes() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _db
        .collection('disputes')
        .where('buyerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> getAllDisputes() {
    return _db
        .collection('disputes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  Future<void> resolveDispute({
    required String disputeId,
    required String resolution,
    required bool refund,
  }) async {
    await _db.collection('disputes').doc(disputeId).update({
      'status': refund ? 'refunded' : 'resolved',
      'resolution': resolution,
      'resolvedBy': _auth.currentUser?.uid ?? '',
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDisputeStatus(String disputeId, String status) async {
    await _db.collection('disputes').doc(disputeId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
