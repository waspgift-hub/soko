import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'cloudinary_service.dart';

class StatusService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const int statusExpiryHours = 24;

  Future<void> addTextStatus(String text, {String? backgroundColor}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final expiresAt = DateTime.now().add(const Duration(hours: statusExpiryHours));

    await _db.collection('statuses').add({
      'userId': user.uid,
      'type': 'text',
      'text': text,
      'backgroundColor': backgroundColor ?? '#2D6A4F',
      'imageUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'views': [],
    });
  }

  Future<void> addImageStatus(XFile image) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final imageUrl = await CloudinaryService.uploadImage(image, folder: 'statuses');
    final expiresAt = DateTime.now().add(const Duration(hours: statusExpiryHours));

    await _db.collection('statuses').add({
      'userId': user.uid,
      'type': 'image',
      'text': '',
      'backgroundColor': '',
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'views': [],
    });
  }

  Stream<List<Map<String, dynamic>>> getMyStatuses() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection('statuses')
        .where('userId', isEqualTo: user.uid)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> getOthersStatuses() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection('statuses')
        .where('userId', isNotEqualTo: user.uid)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  Future<void> viewStatus(String statusId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.collection('statuses').doc(statusId).update({
      'views': FieldValue.arrayUnion([user.uid]),
    });
  }

  Future<void> deleteStatus(String statusId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _db.collection('statuses').doc(statusId).get();
    if (doc.exists && doc.data()?['userId'] == user.uid) {
      await _db.collection('statuses').doc(statusId).delete();
    }
  }

  Future<void> deleteExpiredStatuses() async {
    final expired = await _db
        .collection('statuses')
        .where('expiresAt', isLessThan: Timestamp.now())
        .get();

    final batch = _db.batch();
    for (final doc in expired.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
