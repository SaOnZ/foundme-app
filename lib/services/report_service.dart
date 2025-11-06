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
      'status': 'pending', // For you to review in the console
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
