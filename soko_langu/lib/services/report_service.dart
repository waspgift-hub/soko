import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/report_model.dart';

class ReportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> submitReport(Report report) async {
    await _db.collection('reports').add(report.toMap());
  }

  Stream<List<Report>> getReports({String? status}) {
    Query query = _db.collection('reports').orderBy('createdAt', descending: true);
    if (status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
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
