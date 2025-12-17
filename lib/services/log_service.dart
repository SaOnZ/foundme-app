import 'package:cloud_firestore/cloud_firestore.dart';

class LogService {
  // Singleton pattern (same as your other services)
  LogService._();
  static final instance = LogService._();

  // Pointer to the 'logs' collection in Firestore
  final _logs = FirebaseFirestore.instance.collection('logs');

  /// 1. WRITE A LOG
  /// Call this function whenever an important event happens.
  /// Example: LogService.instance.logActivity('Item Closed', 'Item #123 was closed', 'closed');
  Future<void> logActivity(String title, String details, String status) async {
    try {
      await _logs.add({
        'title': title, // e.g., "Post Approved"
        'details': details, // e.g., "Red Wallet (ID: xyz) was approved"
        'status': status, // e.g., "active", "rejected", "banned"
        'timestamp': FieldValue.serverTimestamp(), // Critical for sorting!
      });
    } catch (e) {
      print("Failed to write log: $e");
    }
  }

  /// 2. READ LOGS
  /// This Stream is used by your Admin Dashboard to show the list.
  /// It sorts by newest first and limits to the last 20 events.
  Stream<QuerySnapshot> getRecentLogs() {
    return _logs.orderBy('timestamp', descending: true).limit(20).snapshots();
  }
}
