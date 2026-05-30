import 'package:cloud_firestore/cloud_firestore.dart';

class Report {
  final String id;
  final String reporterId;
  final String reporterName;
  final String reportedUserId;
  final String reportedUserName;
  final String? productId;
  final String? productName;
  final String reason;
  final String description;
  final String status;
  final String? adminNote;
  final DateTime createdAt;

  Report({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.reportedUserId,
    required this.reportedUserName,
    this.productId,
    this.productName,
    required this.reason,
    required this.description,
    this.status = 'pending',
    this.adminNote,
    required this.createdAt,
  });

  factory Report.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Report(
      id: doc.id,
      reporterId: data['reporterId'] ?? '',
      reporterName: data['reporterName'] ?? 'Anonymous',
      reportedUserId: data['reportedUserId'] ?? '',
      reportedUserName: data['reportedUserName'] ?? 'Anonymous',
      productId: data['productId'],
      productName: data['productName'],
      reason: data['reason'] ?? 'other',
      description: data['description'] ?? '',
      status: data['status'] ?? 'pending',
      adminNote: data['adminNote'],
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'reporterId': reporterId,
    'reporterName': reporterName,
    'reportedUserId': reportedUserId,
    'reportedUserName': reportedUserName,
    'productId': productId,
    'productName': productName,
    'reason': reason,
    'description': description,
    'status': status,
    'adminNote': adminNote,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Report copyWith({String? status, String? adminNote}) => Report(
    id: id,
    reporterId: reporterId,
    reporterName: reporterName,
    reportedUserId: reportedUserId,
    reportedUserName: reportedUserName,
    productId: productId,
    productName: productName,
    reason: reason,
    description: description,
    status: status ?? this.status,
    adminNote: adminNote ?? this.adminNote,
    createdAt: createdAt,
  );

  static const List<String> reasons = [
    'fraud',
    'fake_product',
    'scam',
    'inappropriate',
    'harassment',
    'other',
  ];
}
