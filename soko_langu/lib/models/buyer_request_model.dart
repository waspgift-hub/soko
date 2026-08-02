import 'package:cloud_firestore/cloud_firestore.dart';

/// A buyer's "Natafuta Bidhaa" request that sellers browse and unlock.
class BuyerRequest {
  final String id;
  final String buyerUid;
  final String buyerName;
  final String title;
  final String description;
  final double budget;
  final String whatsapp;
  final bool isLocked;
  final List<String> unlockedBy;
  final DateTime createdAt;

  BuyerRequest({
    required this.id,
    required this.buyerUid,
    this.buyerName = '',
    required this.title,
    this.description = '',
    this.budget = 0,
    this.whatsapp = '',
    this.isLocked = true,
    this.unlockedBy = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory BuyerRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BuyerRequest(
      id: doc.id,
      buyerUid: data['buyerUid'] ?? '',
      buyerName: data['buyerName'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      budget: (data['budget'] ?? 0).toDouble(),
      whatsapp: data['whatsapp'] ?? '',
      isLocked: data['isLocked'] ?? true,
      unlockedBy: (data['unlockedBy'] as List?)?.cast<String>() ?? const [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Whether this seller has permanently unlocked the buyer's contact.
  bool isUnlockedFor(String uid) => unlockedBy.contains(uid);
}
