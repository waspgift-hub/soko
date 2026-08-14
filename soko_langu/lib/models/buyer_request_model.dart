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

    // Legacy docs may store budget as a string ("50000") rather than a number;
    // coerce any numeric-ish value without letting parse errors crash the whole stream.
    double budget = 0;
    final rawBudget = data['budget'];
    if (rawBudget is num) {
      budget = rawBudget.toDouble();
    } else if (rawBudget is String) {
      budget = double.tryParse(rawBudget.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    }

    DateTime createdAt = DateTime.now();
    final rawCreated = data['createdAt'];
    if (rawCreated is Timestamp) {
      createdAt = rawCreated.toDate();
    } else if (rawCreated is String) {
      createdAt = DateTime.tryParse(rawCreated) ?? DateTime.now();
    }

    return BuyerRequest(
      id: doc.id,
      buyerUid: data['buyerUid'] ?? '',
      buyerName: data['buyerName'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      budget: budget,
      whatsapp: data['whatsapp'] ?? '',
      isLocked: data['isLocked'] ?? true,
      unlockedBy: (data['unlockedBy'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt: createdAt,
    );
  }

  /// Whether this seller has permanently unlocked the buyer's contact.
  bool isUnlockedFor(String uid) => unlockedBy.contains(uid);
}
