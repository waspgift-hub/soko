import 'package:cloud_firestore/cloud_firestore.dart';

class WalletService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> ensureWallet(String userId) async {
    final doc = await _db.collection('wallets').doc(userId).get();
    if (!doc.exists) {
      await _db.collection('wallets').doc(userId).set({
        'balance': 0,
        'totalEarnings': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<double> getBalance(String userId) async {
    final doc = await _db.collection('wallets').doc(userId).get();
    if (!doc.exists) return 0;
    return (doc.data()?['balance'] as num? ?? 0).toDouble();
  }

  Stream<DocumentSnapshot> streamWallet(String userId) {
    return _db.collection('wallets').doc(userId).snapshots();
  }

  Stream<QuerySnapshot> getTransactions(String userId) {
    return _db
        .collection('revenue_transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
