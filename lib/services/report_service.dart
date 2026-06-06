import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class ReportService {
  ReportService._();
  static final instance = ReportService._();

  final _db = FirebaseFirestore.instance;

  Future<void> submitReport({
    required String reason,
    String? reportedItemId,
    String? reportedUid,
  }) async {
    final reporterUid = AuthService.instance.currentUser?.uid;
    if (reporterUid == null) {
      throw 'You must be logged in to submit a report.';
    }

    if (reportedItemId == null && reportedUid == null) {
      throw 'A report must include an item or a user.';
    }

    await _db.collection('reports').add({
      'reporterUid': reporterUid,
      'reportedItemId': reportedItemId,
      'reportedUid': reportedUid,
      'reason': reason,
      'status': 'pending', // For review in the admin console
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Streams pending reports for the admin console. Ordered client-side to
  /// avoid requiring a composite (status + createdAt) index.
  Stream<List<QueryDocumentSnapshot>> pendingReports({int limit = 200}) {
    return _db
        .collection('reports')
        .where('status', isEqualTo: 'pending')
        .limit(limit)
        .snapshots()
        .map((s) {
          final docs = s.docs.toList();
          docs.sort((a, b) {
            final ta = (a.data()['createdAt'] as Timestamp?);
            final tb = (b.data()['createdAt'] as Timestamp?);
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta); // newest first
          });
          return docs;
        });
  }

  /// Marks a report resolved or dismissed (admin-only per firestore.rules).
  Future<void> resolveReport(String reportId, {required String status}) async {
    await _db.collection('reports').doc(reportId).update({
      'status': status, // 'resolved' | 'dismissed'
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': AuthService.instance.currentUser?.uid,
    });
  }
}
