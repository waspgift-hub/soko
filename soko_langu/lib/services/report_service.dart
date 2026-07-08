import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/report_model.dart';
import 'api_config.dart';

class ReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> submitReport(Report report) async {
    final token = await _auth.currentUser?.getIdToken();
    final resp = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/reports'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(report.toMap()),
    );
    final result = jsonDecode(resp.body);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to submit report');
    }
  }

  Stream<List<Report>> getReports({String? status, String? productId}) {
    Query query = _db.collection('reports').orderBy('createdAt', descending: true);
    if (status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
    }
    if (productId != null && productId.isNotEmpty) {
      query = query.where('productId', isEqualTo: productId);
    }
    return query.snapshots().map((snap) =>
        snap.docs.map((doc) => Report.fromFirestore(doc)).toList());
  }

  Future<void> updateReportStatus(String reportId, String status, {String? adminNote}) async {
    final data = <String, dynamic>{'status': status};
    if (adminNote != null) data['adminNote'] = adminNote;
    await _db.collection('reports').doc(reportId).update(data);
  }

  Future<Report?> getReport(String reportId) async {
    final doc = await _db.collection('reports').doc(reportId).get();
    if (!doc.exists) return null;
    return Report.fromFirestore(doc);
  }
}
