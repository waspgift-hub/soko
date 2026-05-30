import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/status_model.dart';
import '../services/cloudinary_service.dart';

class StatusService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;
  String? get _displayName => _auth.currentUser?.displayName;
  String? get _photoUrl => _auth.currentUser?.photoURL;

  static const Duration _expiryDuration = Duration(hours: 24);

  Future<String> postTextStatus(String text, {String privacy = 'everyone'}) async {
    if (_uid == null) throw Exception('Not logged in');
    final now = DateTime.now();
    final doc = _db.collection('statuses').doc();
    final status = StatusUpdate(
      id: doc.id,
      userId: _uid!,
      userName: _displayName ?? '',
      userImage: _photoUrl,
      type: 'text',
      textContent: text,
      createdAt: now,
      expiresAt: now.add(_expiryDuration),
    );
    await doc.set(status.toMap());
    return doc.id;
  }

  Future<String> postImageStatus(File imageFile, {String? caption, String privacy = 'everyone'}) async {
    if (_uid == null) throw Exception('Not logged in');
    final now = DateTime.now();
    final xfile = XFile(imageFile.path);
    final mediaUrl = await CloudinaryService.uploadImage(xfile);
    final doc = _db.collection('statuses').doc();
    final status = StatusUpdate(
      id: doc.id,
      userId: _uid!,
      userName: _displayName ?? '',
      userImage: _photoUrl,
      type: 'image',
      mediaUrl: mediaUrl,
      textContent: caption,
      createdAt: now,
      expiresAt: now.add(_expiryDuration),
    );
    await doc.set(status.toMap());
    return doc.id;
  }

  Future<String> postVideoStatus(File videoFile, {String? caption, String privacy = 'everyone'}) async {
    if (_uid == null) throw Exception('Not logged in');
    final now = DateTime.now();
    final xfile = XFile(videoFile.path);
    final mediaUrl = await CloudinaryService.uploadVideo(xfile);
    final doc = _db.collection('statuses').doc();
    final status = StatusUpdate(
      id: doc.id,
      userId: _uid!,
      userName: _displayName ?? '',
      userImage: _photoUrl,
      type: 'video',
      mediaUrl: mediaUrl,
      textContent: caption,
      createdAt: now,
      expiresAt: now.add(_expiryDuration),
    );
    await doc.set(status.toMap());
    return doc.id;
  }

  Stream<List<StatusUpdate>> getMyStatuses() {
    if (_uid == null) return Stream.value([]);
    return _db
        .collection('statuses')
        .where('userId', isEqualTo: _uid)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StatusUpdate.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) {
            final cmp = b.expiresAt.compareTo(a.expiresAt);
            if (cmp != 0) return cmp;
            return b.createdAt.compareTo(a.createdAt);
          }));
  }

  Stream<List<StatusViewerState>> getAllStatuses() {
    if (_uid == null) return Stream.value([]);
    return _db
        .collection('statuses')
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .snapshots()
        .map((snap) {
      final Map<String, List<StatusUpdate>> grouped = {};
      for (final doc in snap.docs) {
        final status = StatusUpdate.fromMap(doc.id, doc.data());
        if (status.userId == _uid) continue;
        grouped.putIfAbsent(status.userId, () => []);
        grouped[status.userId]!.add(status);
      }
      return grouped.entries.map((entry) {
        final updates = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return StatusViewerState(
          userId: entry.key,
          userName: updates.first.userName,
          userImage: updates.first.userImage,
          updates: updates,
          hasUnviewed: updates.any((s) => !s.viewers.contains(_uid)),
        );
      }).toList();
    });
  }

  Future<void> markStatusViewed(String statusId) async {
    if (_uid == null) return;
    final doc = _db.collection('statuses').doc(statusId);
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(doc);
      if (!snapshot.exists) return;
      final viewers = List<String>.from(snapshot.data()?['viewers'] ?? []);
      if (!viewers.contains(_uid)) {
        viewers.add(_uid!);
        tx.update(doc, {'viewers': viewers});
      }
    });
  }

  Future<void> deleteStatus(String statusId) async {
    if (_uid == null) return;
    final doc = _db.collection('statuses').doc(statusId);
    final snap = await doc.get();
    if (snap.exists && snap.data()?['userId'] == _uid) {
      await doc.delete();
    }
  }

  Future<void> deleteAllMyStatuses() async {
    if (_uid == null) return;
    final snap = await _db
        .collection('statuses')
        .where('userId', isEqualTo: _uid)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> cleanupExpiredStatuses() async {
    final snap = await _db
        .collection('statuses')
        .where('expiresAt', isLessThan: Timestamp.now())
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    if (snap.docs.isNotEmpty) {
      await batch.commit();
      debugPrint('Cleaned up ${snap.docs.length} expired statuses');
    }
  }
}
